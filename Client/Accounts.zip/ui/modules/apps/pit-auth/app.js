angular.module("beamng.apps")
.directive("pitAuth", function() {
  return {
    restrict: "E",
    templateUrl: "/ui/modules/apps/pit-auth/app.html",
    replace: true,
    controller: function($scope) {

      $scope.showAuth = false;
      $scope.tab      = "login";
      $scope.form     = { username: "", password: "" };
      $scope.error    = "";
      $scope.loading  = false;
      $scope.hasSaved = false;

      var savedUsername      = null;
      var savedHash          = null;
      var serverTranslations = {};

      window.pitDisplayNames = {};

      try {
        savedUsername = localStorage.getItem("pit_username");
        savedHash     = localStorage.getItem("pit_password_hash");
      } catch(e) {}

      $scope.hasSaved = !!(savedHash);

      var fallback = {
        "auth_login_title":          "Sign In",
        "auth_register_title":       "Create Account",
        "auth_login":                "Sign In",
        "auth_register":             "Register",
        "auth_username":             "Username",
        "auth_password":             "Password",
        "auth_username_placeholder": "3-20 chars, letters/numbers/_/-",
        "auth_password_placeholder": "Your password",
        "auth_password_saved":       "Leave empty to sign in with saved password",
        "auth_do_login":             "Sign In",
        "auth_do_register":          "Create Account",
        "auth_loading":              "Please wait...",
        "auth_empty_fields":         "Please fill in all fields.",
        "auth_username_length":      "Username must be 3-20 characters.",
        "auth_invalid":              "Invalid data.",
        "auth_username_invalid":     "Username: letters, numbers, _ or - only.",
        "auth_username_taken":       "Username already taken.",
        "auth_not_found":            "Username not found.",
        "auth_wrong_password":       "Incorrect password.",
        "auth_failed":               "Authentication failed."
      };

      $scope.t = function(key, vars) {
        var text = serverTranslations[key] || fallback[key] || key;
        if (vars) {
          for (var k in vars) text = text.replace("${" + k + "}", vars[k]);
        }
        return text;
      };

      function closeAuth() { $scope.showAuth = false; }

      function sha256(msg) {
        return crypto.subtle.digest("SHA-256", new TextEncoder().encode(msg)).then(function(h) {
          return Array.from(new Uint8Array(h))
            .map(function(b) { return b.toString(16).padStart(2, "0"); }).join("");
        });
      }

      $scope.setTab = function(t) {
        $scope.$applyAsync(function() { $scope.tab = t; $scope.error = ""; });
      };

      $scope.submit = function() {
        var uname = ($scope.form.username || "").trim();
        var pass  = $scope.form.password  || "";

        if (!uname) {
          $scope.$applyAsync(function() { $scope.error = $scope.t("auth_empty_fields"); });
          return;
        }
        if (uname.length < 3 || uname.length > 20) {
          $scope.$applyAsync(function() { $scope.error = $scope.t("auth_username_length"); });
          return;
        }

        if (!pass && savedHash && savedUsername === uname && $scope.tab === "login") {
          $scope.$applyAsync(function() { $scope.loading = true; $scope.error = ""; });
          var p = JSON.stringify({ mode: "login", username: uname, hash: savedHash });
          if (window.bngApi) window.bngApi.engineLua("TriggerServerEvent(\"PIT_AUTH_Auth\", [==[" + p + "]==])");
          return;
        }

        if (!pass) {
          $scope.$applyAsync(function() { $scope.error = $scope.t("auth_empty_fields"); });
          return;
        }

        $scope.$applyAsync(function() { $scope.loading = true; $scope.error = ""; });
        sha256(pass).then(function(hash) {
          var p = JSON.stringify({ mode: $scope.tab, username: uname, hash: hash });
          if (window.bngApi) window.bngApi.engineLua("TriggerServerEvent(\"PIT_AUTH_Auth\", [==[" + p + "]==])");
          try {
            localStorage.setItem("pit_username",      uname);
            localStorage.setItem("pit_password_hash", hash);
          } catch(e) {}
        });
      };

      function handleStatus(data) {
        if (!data || !data.translations) return;
        serverTranslations = data.translations;
        $scope.$applyAsync(function() {
          if (data.auth_required) {
            $scope.showAuth = true;
            $scope.loading  = false;
            $scope.hasSaved = !!(savedHash);
            if (savedUsername) $scope.form.username = savedUsername;
          } else {
            closeAuth();
          }
        });
      }

      function handleResult(data) {
        if (!data) return;
        $scope.$applyAsync(function() {
          $scope.loading = false;
          if (data.ok) {
            closeAuth();
          } else {
            $scope.error = $scope.t(data.error || "auth_failed");
            savedHash    = null;
            try { localStorage.removeItem("pit_password_hash"); } catch(e) {}
          }
        });
      }

      function handleDisplayNames(data) {
        if (!data) return;
        window.pitDisplayNames = data;
        if (window.bngApi) window.bngApi.engineLua("UI.updatePlayersList()");
      }

      $scope.$on("PIT_AUTH_Status",  function(e, data) { handleStatus(data); });
      $scope.$on("PIT_AUTH_Result",  function(e, data) { handleResult(data); });
      $scope.$on("PIT_DisplayNames", function(e, data) { handleDisplayNames(data); });

      try {
        if (typeof guihooks !== "undefined" && guihooks.on) {
          guihooks.on("PIT_AUTH_Status", function(data) {
            handleStatus(data);
            if (data && data.auth_required && savedUsername && savedHash && window.bngApi) {
              var p = JSON.stringify({ mode: "login", username: savedUsername, hash: savedHash });
              window.bngApi.engineLua("TriggerServerEvent(\"PIT_AUTH_Auth\", [==[" + p + "]==])");
            }
          });
          guihooks.on("PIT_AUTH_Result",  function(data) { handleResult(data); });
          guihooks.on("PIT_DisplayNames", function(data) { handleDisplayNames(data); });
        }
      } catch(e) { console.error("[PIT_Auth]", e); }

      if (window.bngApi && typeof window.bngApi.engineLua === "function") {
        window.bngApi.engineLua("TriggerServerEvent(\"PIT_AUTH_RequestStatus\", \"\")");
      }
    }
  };
});