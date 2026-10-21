// Everything you need to change before the site goes live, in one place.
// Prices are written into the pages too (so they show without JavaScript); change both if they ever move.
window.HAVEN = {
  version: "1.0",
  refundDays: 30,

  // Stripe Payment Links, one per plan (Stripe Dashboard › Payment Links › New).
  // Leave a link empty and its Buy button explains that checkout isn't connected yet.
  checkout: {
    one: "",   // 1 Mac, $49
    three: "", // 3 Macs, $79
    five: "",  // 5 Macs, $99
  },

  // The notarized DMG, e.g. "https://downloads.yourdomain.com/Haven-1.0.dmg".
  downloadURL: "",
  downloadSize: "11.2 MB",

  supportEmail: "support@yourdomain.com",
  privacyEmail: "privacy@yourdomain.com",
};
