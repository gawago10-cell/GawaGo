from django.contrib.auth import get_user_model
from django.test import TestCase
from django.urls import reverse

from apps.accounts.models import UserProfile
from apps.chat.models import Message
from apps.common.authentication import create_jwt_token
from apps.jobs.models import JobApplication, JobPosting

User = get_user_model()


def authenticate(client, user):
    client.defaults["HTTP_AUTHORIZATION"] = f"Bearer {create_jwt_token({'user_id': user.id})}"


class ChatTests(TestCase):
    def setUp(self):
        self.household = User.objects.create_user(username="chat-household", password="password", first_name="Hana")
        UserProfile.objects.create(user=self.household, role=UserProfile.ROLE_HOUSEHOLD)
        self.worker = User.objects.create_user(username="chat-worker", password="password", first_name="Wes")
        UserProfile.objects.create(user=self.worker, role=UserProfile.ROLE_WORKER)
        self.outsider = User.objects.create_user(username="chat-outsider", password="password")
        UserProfile.objects.create(user=self.outsider, role=UserProfile.ROLE_WORKER)

        self.job = JobPosting.objects.create(
            household=self.household,
            title="Deep clean",
            job_type="House Cleaning",
            required_skill="House Cleaning",
            schedule="Saturday",
            location_label="Isabang, Tayabas",
            latitude="13.9622745",
            longitude="121.5632841",
            service_rate="500.00",
            status=JobPosting.STATUS_ASSIGNED,
        )
        self.hire = JobApplication.objects.create(job=self.job, worker=self.worker, status=JobApplication.STATUS_HIRED)
        self.messages_url = reverse("conversation-messages", args=[self.hire.id])

    def send(self, user, content):
        authenticate(self.client, user)
        return self.client.post(self.messages_url, {"content": content}, content_type="application/json")

    def test_household_can_send_and_sender_is_request_user(self):
        response = self.client.post(
            self.messages_url,
            {"content": "hello", "sender": self.worker.id},
            content_type="application/json",
            HTTP_AUTHORIZATION=f"Bearer {create_jwt_token({'user_id': self.household.id})}",
        )

        self.assertEqual(response.status_code, 201)
        self.assertEqual(response.json()["content"], "hello")
        self.assertTrue(response.json()["is_mine"])
        self.assertEqual(Message.objects.get().sender, self.household)

    def test_worker_can_read_household_message(self):
        self.send(self.household, "hello")
        authenticate(self.client, self.worker)

        response = self.client.get(self.messages_url)

        self.assertEqual(response.status_code, 200)
        self.assertEqual([m["content"] for m in response.json()], ["hello"])
        self.assertFalse(response.json()[0]["is_mine"])
        self.assertEqual(response.json()[0]["sender_name"], "Hana")

    def test_unrelated_user_gets_403(self):
        self.send(self.household, "hello")
        authenticate(self.client, self.outsider)

        self.assertEqual(self.client.get(self.messages_url).status_code, 403)
        self.assertEqual(self.send(self.outsider, "hi").status_code, 403)
        self.assertEqual(self.client.post(reverse("conversation-read", args=[self.hire.id])).status_code, 403)
        self.assertEqual(Message.objects.count(), 1)

    def test_empty_and_whitespace_messages_rejected(self):
        self.assertEqual(self.send(self.household, "").status_code, 400)
        self.assertEqual(self.send(self.household, "   \n ").status_code, 400)
        self.assertEqual(self.send(self.household, "x" * 2001).status_code, 400)
        self.assertEqual(Message.objects.count(), 0)

    def test_chat_closed_unless_hire_is_active(self):
        self.job.status = JobPosting.STATUS_CANCELLED
        self.job.save(update_fields=["status"])
        self.assertEqual(self.send(self.household, "hello").status_code, 403)

        self.job.status = JobPosting.STATUS_ASSIGNED
        self.job.save(update_fields=["status"])
        self.hire.status = JobApplication.STATUS_PENDING
        self.hire.save(update_fields=["status"])
        self.assertEqual(self.send(self.household, "hello").status_code, 403)

    def test_after_returns_only_newer_messages(self):
        first = self.send(self.household, "one").json()
        self.send(self.worker, "two")
        authenticate(self.client, self.household)

        response = self.client.get(self.messages_url, {"after": first["id"]})

        self.assertEqual([m["content"] for m in response.json()], ["two"])
        self.assertEqual(self.client.get(self.messages_url, {"after": "abc"}).status_code, 400)

    def test_conversation_list_and_mark_read(self):
        self.send(self.household, "hello")
        authenticate(self.client, self.worker)

        conversations = self.client.get(reverse("conversation-list")).json()
        self.assertEqual(len(conversations), 1)
        self.assertEqual(conversations[0]["id"], self.hire.id)
        self.assertEqual(conversations[0]["other_party"]["name"], "Hana")
        self.assertEqual(conversations[0]["last_message"]["content"], "hello")
        self.assertEqual(conversations[0]["unread_count"], 1)

        read = self.client.post(reverse("conversation-read", args=[self.hire.id]))
        self.assertEqual(read.json(), {"marked_read": 1})
        self.assertEqual(self.client.get(reverse("conversation-list")).json()[0]["unread_count"], 0)

        authenticate(self.client, self.outsider)
        self.assertEqual(self.client.get(reverse("conversation-list")).json(), [])
