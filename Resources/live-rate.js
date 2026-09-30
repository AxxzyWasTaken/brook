// Live video without a hitch every few seconds.
//
// A live player (X's, among others) keeps up with the broadcast by nudging playbackRate: 1.04 when
// behind, back to exactly 1 once caught up. On macOS every step across 1 makes CoreMedia rebuild the
// audio path and hold the picture still meanwhile. Two speeds that are both off 1 switch without a break,
// so once a page has nudged a video, a later 1 is played at 1.0001 while the page still reads back 1.
// Speeds picked from a menu (1.25, 1.5, 2) never start this, and a page that never nudges is untouched.
//
// Adapted from Search by Office Commun (MIT License, Copyright (c) 2026 Office Commun), LiveRate.swift.
(function () {
  var proto = HTMLMediaElement.prototype;
  var plain = Object.getOwnPropertyDescriptor(proto, 'playbackRate');
  if (!plain || !plain.get || !plain.set) return;
  var nudge = 0.1, beside = 1.0001;   // off 1 by this much at most: a player catching up, not a choice
  var nudged = new WeakSet(), asked = new WeakMap();
  var smooth = {
    get playbackRate() {
      var now = plain.get.call(this), was = asked.get(this);
      // Changed some other way since (the video's own controls, an extension): what it is now is the answer.
      return was && Math.abs(now - was.played) < 1e-9 ? was.asked : now;
    },
    set playbackRate(value) {
      var rate = +value;
      var played = rate === 1 && nudged.has(this) ? beside : rate;
      plain.set.call(this, played);   // throws for an invalid rate, before anything is kept
      if (rate !== 1 && Math.abs(rate - 1) <= nudge) nudged.add(this);
      if (played !== rate) asked.set(this, { asked: rate, played: played });
      else asked.delete(this);
    }
  };
  var made = Object.getOwnPropertyDescriptor(smooth, 'playbackRate');
  try {
    Object.defineProperty(proto, 'playbackRate', {
      get: made.get, set: made.set, enumerable: plain.enumerable, configurable: true
    });
  } catch (e) {}
})();
