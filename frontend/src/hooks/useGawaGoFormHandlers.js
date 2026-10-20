import { sanitizePhilippinesPhone } from "../utils/formatters";
import { readFileAsDataUrl } from "../utils/mediaUtils";
import { normalizeBarangayName } from "../utils/locationUtils";
import { MAX_WORKER_SKILLS } from "../constants/appConstants";

export function useGawaGoFormHandlers({
  setHouseholdForm,
  setHouseholdJobCoordinates,
  setHouseholdJobForm,
  setHouseholdJobLocationPreview,
  setHouseholdProfileForm,
  setLoginError,
  setLoginForm,
  setRegisterErrors,
  setVerificationForm,
  setWorkerForm,
  setWorkerProfileForm,
  syncHouseholdJobBarangayLocation,
}) {
  // Typing into a flagged field clears just that field's error, so the red
  // state goes away as soon as the person starts fixing it.
  function clearRegisterError(name) {
    setRegisterErrors?.((prev) => {
      if (!prev || !prev[name]) return prev;
      const { [name]: _removed, ...rest } = prev;
      return rest;
    });
  }

  function handleLoginChange(event) {
    const { name, value } = event.target;
    setLoginError("");
    setLoginForm((prev) => ({
      ...prev,
      [name]: value,
    }));
  }

  function handleWorkerChange(event) {
    const { name, value } = event.target;
    clearRegisterError(name);
    if (name === "barangay") clearRegisterError("streetAddress");
    if (name === "password") clearRegisterError("confirmPassword");
    if (name === "phone") {
      setWorkerForm((prev) => ({
        ...prev,
        phone: sanitizePhilippinesPhone(value),
      }));
      return;
    }
    if (name === "customSkill") {
      setWorkerForm((prev) => ({
        ...prev,
        customSkill: value,
      }));
      return;
    }
    if (name === "barangay") {
      const barangay = normalizeBarangayName(value);
      setWorkerForm((prev) => ({
        ...prev,
        barangay,
        streetAddress: barangay && !prev.streetAddress ? `Barangay ${barangay}, Tayabas City` : prev.streetAddress,
        latitude: null,
        longitude: null,
        locationLabel: "",
        locationSource: "",
        locationWarning: "",
        locationAccuracy: "",
      }));
      return;
    }
    if (name === "streetAddress") {
      setWorkerForm((prev) => ({
        ...prev,
        streetAddress: value,
        latitude: null,
        longitude: null,
        locationLabel: "",
        locationSource: "",
        locationWarning: "",
        locationAccuracy: "",
      }));
      return;
    }
    setWorkerForm((prev) => ({
      ...prev,
      [name]: value,
    }));
  }

  function handleHouseholdChange(event) {
    const { name, value } = event.target;
    clearRegisterError(name);
    if (name === "password") clearRegisterError("confirmPassword");
    if (name === "phone") {
      setHouseholdForm((prev) => ({
        ...prev,
        phone: sanitizePhilippinesPhone(value),
      }));
      return;
    }
    setHouseholdForm((prev) => ({
      ...prev,
      [name]: value,
    }));
  }

  function handleHouseholdProfileChange(event) {
    const { name, value, files } = event.target;
    if (name === "profilePhoto") {
      const file = files?.[0];
      if (!file) {
        setHouseholdProfileForm((prev) => ({
          ...prev,
          profilePhotoFile: null,
          profilePhotoName: "",
          profilePhotoPreview: "",
        }));
        return;
      }
      setHouseholdProfileForm((prev) => ({
        ...prev,
        profilePhotoFile: file,
        profilePhotoName: file.name,
        profilePhotoPreview: "",
      }));
      readFileAsDataUrl(file)
        .then((preview) =>
          setHouseholdProfileForm((prev) => ({
            ...prev,
            profilePhotoFile: file,
            profilePhotoName: file.name,
            profilePhotoPreview: preview,
          })),
        )
        .catch(() =>
          setHouseholdProfileForm((prev) => ({
            ...prev,
            profilePhotoPreview: "",
          })),
        );
      return;
    }
    setHouseholdProfileForm((prev) => ({
      ...prev,
      [name]: value,
    }));
  }

  function handleHouseholdJobChange(event) {
    const { name, value } = event.target;
    if (name === "serviceType") {
      setHouseholdJobForm((prev) => ({
        ...prev,
        serviceType: value,
        customServiceType: value === "Other" ? prev.customServiceType : "",
      }));
      return;
    }
    if (name === "customServiceType") {
      setHouseholdJobForm((prev) => ({
        ...prev,
        customServiceType: value.slice(0, 100),
      }));
      return;
    }
    if (name === "barangay") {
      setHouseholdJobForm((prev) => ({
        ...prev,
        barangay: value,
        streetAddress: value ? `Barangay ${value}, Tayabas City` : prev.streetAddress,
      }));
      if (value) {
        syncHouseholdJobBarangayLocation(value);
      } else {
        setHouseholdJobCoordinates(null);
        setHouseholdJobLocationPreview(null);
      }
      return;
    }
    if (name === "streetAddress") {
      setHouseholdJobCoordinates(null);
      setHouseholdJobLocationPreview(null);
    }
    setHouseholdJobForm((prev) => ({
      ...prev,
      [name]: value,
    }));
  }

  function handleWorkerProfileChange(event) {
    const { name, value, type, checked, files } = event.target;
    if (name === "profilePhoto") {
      const file = files?.[0];
      if (!file) {
        setWorkerProfileForm((prev) => ({
          ...prev,
          profilePhotoFile: null,
          profilePhotoPreview: "",
        }));
        return;
      }
      setWorkerProfileForm((prev) => ({
        ...prev,
        profilePhotoFile: file,
        profilePhotoPreview: "",
      }));
      readFileAsDataUrl(file)
        .then((preview) =>
          setWorkerProfileForm((prev) => ({
            ...prev,
            profilePhotoFile: file,
            profilePhotoPreview: preview,
          })),
        )
        .catch(() =>
          setWorkerProfileForm((prev) => ({
            ...prev,
            profilePhotoPreview: "",
          })),
        );
      return;
    }
    if (name === "barangay" || name === "streetAddress") {
      setWorkerProfileForm((prev) => ({
        ...prev,
        [name]: value,
        latitude: null,
        longitude: null,
        locationLabel: "",
        locationSource: "",
        locationWarning: "",
        locationAccuracy: "",
      }));
      return;
    }
    setWorkerProfileForm((prev) => ({
      ...prev,
      [name]: type === "checkbox" ? checked : value,
    }));
  }

  function handleVerificationChange(event) {
    const { name, value, files } = event.target;
    if (name === "primaryId") {
      const file = files?.[0];
      if (!file) {
        setVerificationForm((prev) => ({
          ...prev,
          primaryIdName: "",
          primaryIdFile: null,
          primaryIdPreview: "",
        }));
        return;
      }
      setVerificationForm((prev) => ({
        ...prev,
        primaryIdName: file.name,
        primaryIdFile: file,
        primaryIdPreview: "",
      }));
      readFileAsDataUrl(file)
        .then((preview) =>
          setVerificationForm((prev) => ({
            ...prev,
            primaryIdName: file.name,
            primaryIdFile: file,
            primaryIdPreview: preview,
          })),
        )
        .catch(() =>
          setVerificationForm((prev) => ({
            ...prev,
            primaryIdPreview: "",
          })),
        );
      return;
    }
    if (name === "secondaryDoc") {
      const file = files?.[0];
      if (!file) {
        setVerificationForm((prev) => ({
          ...prev,
          secondaryDocName: "",
          secondaryDocFile: null,
          secondaryDocPreview: "",
        }));
        return;
      }
      setVerificationForm((prev) => ({
        ...prev,
        secondaryDocName: file.name,
        secondaryDocFile: file,
        secondaryDocPreview: "",
      }));
      readFileAsDataUrl(file)
        .then((preview) =>
          setVerificationForm((prev) => ({
            ...prev,
            secondaryDocName: file.name,
            secondaryDocFile: file,
            secondaryDocPreview: preview,
          })),
        )
        .catch(() =>
          setVerificationForm((prev) => ({
            ...prev,
            secondaryDocPreview: "",
          })),
        );
      return;
    }
    setVerificationForm((prev) => ({
      ...prev,
      [name]: value,
    }));
  }

  function toggleSkill(skill) {
    setWorkerForm((prev) => {
      const exists = prev.skills.includes(skill);
      if (!exists && prev.skills.length >= MAX_WORKER_SKILLS) {
        alert(`You can select up to ${MAX_WORKER_SKILLS} skills only.`);
        return prev;
      }
      return {
        ...prev,
        skills: exists ? prev.skills.filter((s) => s !== skill) : [...prev.skills, skill],
      };
    });
  }

  function toggleWorkerProfileSkill(skill) {
    setWorkerProfileForm((prev) => {
      const exists = prev.skills.includes(skill);
      if (!exists && prev.skills.length >= MAX_WORKER_SKILLS) {
        alert(`You can select up to ${MAX_WORKER_SKILLS} skills only.`);
        return prev;
      }
      return {
        ...prev,
        skills: exists ? prev.skills.filter((s) => s !== skill) : [...prev.skills, skill],
      };
    });
  }

  return {
    handleHouseholdChange,
    handleHouseholdJobChange,
    handleHouseholdProfileChange,
    handleLoginChange,
    handleVerificationChange,
    handleWorkerChange,
    handleWorkerProfileChange,
    toggleSkill,
    toggleWorkerProfileSkill,
  };
}
