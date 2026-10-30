/**
 * Stolen & Delayed Orders: signed links to the delivery map page (D-107).
 *
 * The chat can't draw the map card in an Experience site (G-137), so for an approved claim the agent sends a link
 * to the site's /delivery-map page instead. The link carries the order, the customer, the total and an expiry,
 * signed with HMAC-SHA256 and a key that never leaves Salesforce (CARES_Map_Link_Setting__c, set by
 * scripts/apex/setup-delivery-map-link.apex). The page is opened by a guest with no object access, so view()
 * reads the telemetry in system mode, but only after the signature and the expiry check out. Without a valid
 * link it returns nothing. Writes nothing and moves no money.
 */
public without sharing class CARES_DeliveryMapLink {
  private static final Pattern ORDER_ID_FORMAT = Pattern.compile(
    'PR-[0-9]{6}-[A-Z0-9]{7}'
  );
  private static final Integer DEFAULT_MINUTES = 30;

  // Tests set these instead of the org's setting, site and clock
  @TestVisible
  private static CARES_Map_Link_Setting__c settingOverride;
  @TestVisible
  private static String baseUrlOverride;
  @TestVisible
  private static Long nowOverride;

  /**
   * The signed link for one approved claim, or null when links are not set up (no key or no site), so the
   * agent goes on without it.
   */
  public static String issue(
    String orderId,
    String contactId,
    Decimal orderTotal,
    String currencyIsoCode
  ) {
    CARES_Map_Link_Setting__c s = setting();
    String key = s == null ? null : s.Signing_Key__c;
    String base = baseUrl(s);
    if (
      String.isBlank(key) ||
      String.isBlank(base) ||
      String.isBlank(orderId) ||
      String.isBlank(contactId)
    ) {
      return null;
    }
    Integer minutes = s.Minutes__c == null ||
      s.Minutes__c <= 0
      ? DEFAULT_MINUTES
      : s.Minutes__c.intValue();
    Long expires = now() + minutes * 60;
    String payload = String.join(
      new List<String>{
        orderId,
        contactId,
        orderTotal == null ? '' : String.valueOf(orderTotal.setScale(2)),
        currencyIsoCode == null ? '' : currencyIsoCode,
        String.valueOf(expires)
      },
      '|'
    );
    String body = encode(Blob.valueOf(payload));
    return base.removeEnd('/') +
      '/delivery-map?t=' +
      body +
      '.' +
      sign(body, key);
  }

  /** The card of a valid, unexpired link; null for anything else. Called by the caresDeliveryMapPage LWC. */
  @AuraEnabled
  public static CARES_GeofenceCardView view(String token) {
    CARES_Map_Link_Setting__c s = setting();
    String key = s == null ? null : s.Signing_Key__c;
    if (
      String.isBlank(key) ||
      String.isBlank(token) ||
      token.countMatches('.') != 1
    ) {
      return null;
    }
    String body = token.substringBefore('.');
    String signature = token.substringAfter('.');
    if (!sameText(sign(body, key), signature)) {
      return null;
    }
    List<String> parts;
    try {
      parts = decode(body).toString().split('\\|', -1);
    } catch (Exception e) {
      return null;
    }
    if (parts.size() != 5 || !ORDER_ID_FORMAT.matcher(parts[0]).matches()) {
      return null;
    }
    Long expires;
    try {
      expires = Long.valueOf(parts[4]);
    } catch (Exception e) {
      return null;
    }
    if (expires < now()) {
      return null;
    }
    CARES_GeofenceMapController.View v = CARES_GeofenceMapController.build(
      parts[0],
      null,
      AccessLevel.SYSTEM_MODE
    );
    if (v.found != true || v.hasCoordinates != true) {
      return null;
    }
    Decimal total = String.isBlank(parts[2]) ? null : Decimal.valueOf(parts[2]);
    return CARES_GeofenceCardView.fromView(
      v,
      parts[0],
      total,
      String.isBlank(parts[3]) ? null : parts[3]
    );
  }

  private static CARES_Map_Link_Setting__c setting() {
    return settingOverride != null
      ? settingOverride
      : CARES_Map_Link_Setting__c.getOrgDefaults();
  }

  // The site's own URL, found by its name, so no URL or id lives in the repo
  private static String baseUrl(CARES_Map_Link_Setting__c s) {
    if (baseUrlOverride != null) {
      return baseUrlOverride;
    }
    if (s == null) {
      return null;
    }
    // Saved by the setup script: the agent user can't look the site up itself
    if (String.isNotBlank(s.Site_Url__c)) {
      return s.Site_Url__c;
    }
    return siteUrl(s.Site_Name__c);
  }

  // The site's own URL, found by its name, so no URL or id lives in the repo. Needs a user who can see the site
  public static String siteUrl(String siteName) {
    if (String.isBlank(siteName)) {
      return null;
    }
    try {
      List<Network> sites = [SELECT Id FROM Network WHERE Name = :siteName LIMIT 1];
      return sites.isEmpty() ? null : ConnectApi.Communities.getCommunity(sites[0].Id).siteUrl;
    } catch (Exception e) {
      return null;
    }
  }

  private static Long now() {
    return nowOverride != null ? nowOverride : Datetime.now().getTime() / 1000;
  }

  private static String sign(String body, String key) {
    return encode(
      Crypto.generateMac(
        'hmacSHA256',
        Blob.valueOf(body),
        EncodingUtil.base64Decode(key)
      )
    );
  }

  // Compares every character, so the time taken doesn't tell how much of a forged signature was right
  private static Boolean sameText(String a, String b) {
    if (a == null || b == null || a.length() != b.length()) {
      return false;
    }
    Integer diff = 0;
    for (Integer i = 0; i < a.length(); i++) {
      diff |= a.charAt(i) ^ b.charAt(i);
    }
    return diff == 0;
  }

  // base64url without padding, safe in a URL
  private static String encode(Blob b) {
    return EncodingUtil.base64Encode(b)
      .replace('+', '-')
      .replace('/', '_')
      .remove('=');
  }

  private static Blob decode(String s) {
    String b64 = s.replace('-', '+').replace('_', '/');
    while (Math.mod(b64.length(), 4) != 0) {
      b64 += '=';
    }
    return EncodingUtil.base64Decode(b64);
  }
}
