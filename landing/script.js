const revealItems = document.querySelectorAll(".reveal");
const menuToggle = document.querySelector(".mac-menubar .menubar-icon.active");
const macContent = document.querySelector(".mac-content");
const keepAwakeInput = document.querySelector('.app-switch-input[aria-label="Keep Mac Awake"]');
const timerButton = document.querySelector(".app-menu-setting");
const timerOptions = document.querySelector(".app-timer-options");
const timerValue = document.querySelector(".app-menu-value");
const timerOptionButtons = document.querySelectorAll(".app-timer-options button");
const updateButton = document.querySelector(".app-update-action");
let selectedTimerMinutes = 0;
let remainingTimerSeconds = 0;
let timerInterval;

if ("scrollRestoration" in history) {
  history.scrollRestoration = "manual";
}

const scrollToTop = () => {
  try {
    document.documentElement.scrollTop = 0;
    document.body.scrollTop = 0;
  } catch {}

  if (typeof window.scrollTo === "function") {
    window.scrollTo({ top: 0, left: 0, behavior: "auto" });
  }
};

scrollToTop();
window.addEventListener("pageshow", scrollToTop);
window.addEventListener("load", scrollToTop);

if ("IntersectionObserver" in window) {
  const observer = new IntersectionObserver(
    (entries) => {
      entries.forEach((entry) => {
        if (entry.isIntersecting) {
          entry.target.classList.add("is-visible");
          observer.unobserve(entry.target);
        }
      });
    },
    { threshold: 0.16 }
  );

  revealItems.forEach((item) => observer.observe(item));
} else {
  revealItems.forEach((item) => item.classList.add("is-visible"));
}

if (menuToggle && macContent) {
  const setMenuOpen = (isOpen) => {
    macContent.classList.toggle("is-menu-open", isOpen);
    menuToggle.setAttribute("aria-expanded", String(isOpen));
  };

  window.setTimeout(() => setMenuOpen(true), 520);

  menuToggle.addEventListener("click", () => {
    setMenuOpen(!macContent.classList.contains("is-menu-open"));
  });
}

const labelForMinutes = (minutes) => {
  if (minutes === 0) {
    return "Infinity";
  }

  if (minutes < 60) {
    return `${minutes} min`;
  }

  const hours = minutes / 60;
  return `${hours}h`;
};

const countdownLabel = (seconds) => {
  const safeSeconds = Math.max(0, seconds);
  const hours = Math.floor(safeSeconds / 3600);
  const minutes = Math.floor((safeSeconds % 3600) / 60);
  const remainingSeconds = safeSeconds % 60;
  const twoDigitMinutes = String(minutes).padStart(2, "0");
  const twoDigitSeconds = String(remainingSeconds).padStart(2, "0");

  if (hours > 0) {
    return `${hours}:${twoDigitMinutes}:${twoDigitSeconds}`;
  }

  return `${minutes}:${twoDigitSeconds}`;
};

const closeTimerOptions = () => {
  if (!timerButton || !timerOptions) {
    return;
  }

  timerButton.setAttribute("aria-expanded", "false");
  timerOptions.hidden = true;
};

const updateTimerLabel = () => {
  if (!timerValue) {
    return;
  }

  if (keepAwakeInput?.checked && remainingTimerSeconds > 0) {
    timerValue.textContent = countdownLabel(remainingTimerSeconds);
    return;
  }

  timerValue.textContent = labelForMinutes(selectedTimerMinutes);
};

const stopTimer = () => {
  window.clearInterval(timerInterval);
  timerInterval = undefined;
  remainingTimerSeconds = 0;
  updateTimerLabel();
};

const startTimer = () => {
  window.clearInterval(timerInterval);

  if (!keepAwakeInput?.checked || selectedTimerMinutes === 0) {
    stopTimer();
    return;
  }

  remainingTimerSeconds = selectedTimerMinutes * 60;
  updateTimerLabel();

  timerInterval = window.setInterval(() => {
    remainingTimerSeconds -= 1;
    updateTimerLabel();

    if (remainingTimerSeconds <= 0) {
      window.clearInterval(timerInterval);
      timerInterval = undefined;

      if (keepAwakeInput) {
        keepAwakeInput.checked = false;
      }

      remainingTimerSeconds = 0;
      updateTimerLabel();
    }
  }, 1000);
};

if (timerButton && timerOptions) {
  timerButton.addEventListener("click", (event) => {
    event.stopPropagation();
    const isOpen = timerButton.getAttribute("aria-expanded") === "true";
    timerButton.setAttribute("aria-expanded", String(!isOpen));
    timerOptions.hidden = isOpen;
  });
}

timerOptionButtons.forEach((optionButton) => {
  optionButton.addEventListener("click", (event) => {
    event.stopPropagation();
    selectedTimerMinutes = Number(optionButton.dataset.minutes || 0);
    closeTimerOptions();
    startTimer();
    updateTimerLabel();
  });
});

keepAwakeInput?.addEventListener("change", () => {
  if (keepAwakeInput.checked) {
    startTimer();
    return;
  }

  stopTimer();
});

updateButton?.addEventListener("click", () => {
  updateButton.classList.remove("is-spinning");
  void updateButton.offsetWidth;
  updateButton.classList.add("is-spinning");
});

document.addEventListener("click", closeTimerOptions);
