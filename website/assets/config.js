// Everything you need to change before the site goes live, in one place.
// Prices are written into the pages too (so they show without JavaScript); change both if they ever move.
window.HAVEN = {
  version: "1.0",
  refundDays: 30,

  // Checkout, through a merchant of record that charges in the buyer's currency, handles sales tax and VAT,
  // and emails the license key (README › Checkout). Each plan's link should send buyers to thanks.html
  // after they pay. Leave a link empty and its Buy button explains that checkout isn't connected yet.
  checkout: {
    provider: "Dodo Payments",
    payWith: "Apple Pay or card", // only what the checkout really offers
    localCurrency: true, // the checkout shows the price in the buyer's currency
    one: "",   // 1 Mac, $49
    three: "", // 3 Macs, $79
    five: "",  // 5 Macs, $99
  },

  // Launch offer: licenses bought while it's on include Haven 2 free. Set on: false when the launch ends;
  // the terms keep the promise for everyone who bought while it was shown.
  launch: {
    on: true,
    endsOn: "", // e.g. "2026-11-30" shows the last day; empty shows no date
  },

  // The notarized DMG, e.g. "https://downloads.yourdomain.com/Haven-1.0.dmg".
  downloadURL: "",
  downloadSize: "11.2 MB",

  supportEmail: "support@yourdomain.com",
  privacyEmail: "privacy@yourdomain.com",
};
