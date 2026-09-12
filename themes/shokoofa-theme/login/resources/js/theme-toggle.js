/* Light/dark switch for the Shokoofa login theme.
   The parent keycloak.v2 theme follows `prefers-color-scheme`; this stores an
   explicit choice and re-applies it after the parent's module script runs. */
(function () {
    "use strict";

    var DARK_CLASS = "pf-v5-theme-dark";
    var STORAGE_KEY = "shokoofa.colorScheme";
    var root = document.documentElement;
    var media = window.matchMedia("(prefers-color-scheme: dark)");
    var button = null;

    function readPreference() {
        try {
            var value = window.localStorage.getItem(STORAGE_KEY);
            return value === "light" || value === "dark" ? value : null;
        } catch (e) {
            return null;
        }
    }

    function writePreference(scheme) {
        try {
            window.localStorage.setItem(STORAGE_KEY, scheme);
        } catch (e) {
            /* private mode / storage disabled - the switch still works per page */
        }
    }

    function resolve() {
        return readPreference() || (media.matches ? "dark" : "light");
    }

    function apply(scheme) {
        root.classList.toggle(DARK_CLASS, scheme === "dark");
        if (button) {
            button.setAttribute("aria-pressed", String(scheme === "dark"));
            button.setAttribute(
                "aria-label",
                scheme === "dark" ? "Switch to light theme" : "Switch to dark theme"
            );
        }
    }

    function icon(paths, name) {
        return (
            '<svg class="sh-theme-toggle__icon sh-theme-toggle__icon--' +
            name +
            '" viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="currentColor" ' +
            'stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">' +
            paths +
            "</svg>"
        );
    }

    function build() {
        button = document.createElement("button");
        button.type = "button";
        button.className = "sh-theme-toggle";
        button.innerHTML =
            icon(
                '<circle cx="12" cy="12" r="4.2"/><path d="M12 2.5v2M12 19.5v2M2.5 12h2M19.5 12h2' +
                    'M5.2 5.2l1.4 1.4M17.4 17.4l1.4 1.4M18.8 5.2l-1.4 1.4M6.6 17.4l-1.4 1.4"/>',
                "sun"
            ) +
            icon('<path d="M20 14.5A8.5 8.5 0 0 1 9.5 4a8.5 8.5 0 1 0 10.5 10.5z"/>', "moon");

        button.addEventListener("click", function () {
            var next = root.classList.contains(DARK_CLASS) ? "light" : "dark";
            writePreference(next);
            apply(next);
        });

        document.body.appendChild(button);
        apply(resolve());
    }

    // Runs from <head>: set the class before first paint to avoid a flash.
    apply(resolve());

    // Module scripts (including the parent's dark-mode script) have already run
    // by this point, so re-applying here wins.
    document.addEventListener("DOMContentLoaded", build);

    media.addEventListener("change", function () {
        apply(resolve());
    });
})();
