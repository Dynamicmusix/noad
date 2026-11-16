// NOAD Ultra-Fast iOS PAC Sinkhole (<12KB, 100% iOS CFNetwork Compatible)
var B = /(^|\.)(doubleclick\.net|googleadservices\.com|googlesyndication\.com|googleads\.com|ads\.youtube\.com|youtubei\.youtube\.com|2mdn\.net|admob\.com|app-measurement\.com|crashlytics\.com|SupersonicAds\.com|ironsrc\.com|ironsource\.mobi|unityads\.unity3d\.com|applovin\.com|applvn\.com|vungle\.com|chartboost\.com|inmobi\.com|tapjoy\.com|tapjoyads\.com|adcolony\.com|fyber\.com|startappservice\.com|smaato\.net|pubmatic\.com|rubiconproject\.com|openx\.net|casalemedia\.com|indexww\.com|criteo\.com|criteo\.net|taboola\.com|outbrain\.com|amazon-adsystem\.com|ads-twitter\.com|ads\.tiktok\.com|byteoversea\.com|pangle\.io|an\.facebook\.com|graph\.facebook\.com|appsflyer\.com|appsflyersdk\.com|adjust\.com|branch\.io|app\.link|kochava\.com|singular\.net|tenjin\.io|airbridge\.io|braze\.com|appboy\.com|clevertap\.com|onesignal\.com|flurry\.com|mixpanel\.com|amplitude\.com|segment\.io|segment\.com|mparticle\.com|scorecardresearch\.com|imrworldwide\.com|quantserve\.com|quantcast\.com|demdex\.net|omtrdc\.net|krxd\.net|bluekai\.com|exelator\.com|mathtag\.com|rlcdn\.com|liadm\.com|id5-sync\.com|adsrvr\.org|adnxs\.com|bidswitch\.net|smartadserver\.com|teads\.tv|MOATads\.com|iasds01\.com|doubleverify\.com|bugsnag\.com|sentry\.io|datadoghq\.com|nr-data\.net|newrelic\.com|Instabug\.com|iadsdk\.apple\.com)$/i;

var G = /^r[0-9]+---sn-.*\.googlevideo\.com$/i;

function FindProxyForURL(url, host) {
  if (!host) return "DIRECT";
  if (B.test(host)) return "PROXY 127.0.0.1:1";
  if ( url.indexOf("&oad=") !== -1 || url.indexOf("&ctier=L") !== -1 || url.indexOf("pagead/") !== -1 || url.indexOf("/ptracking") !== -1 || url.indexOf("/api/stats/ads") !== -1 || url.indexOf("/get_midroll_") !== -1 ) {
    return "PROXY 127.0.0.1:1";
  }
  return "DIRECT";
}
