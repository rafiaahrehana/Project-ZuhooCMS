/// The public marketing site `/api/website/**` serves for a company's
/// subdomain — the same content an anonymous visitor sees, previewed here
/// from inside the app the way the company screen already previews the
/// simpler portal page. Every model in this file mirrors a read-only view of
/// that site; there is no admin endpoint on the backend for editing any of
/// it, so none of these carry a `toJson()` — the three visitor actions
/// (contact, newsletter, service request) are the only writes this module
/// has, and they get their own small request classes at the bottom.
library;

class WebsiteSocialLink {
  const WebsiteSocialLink({this.platform, this.url, this.icon});

  final String? platform;
  final String? url;
  final String? icon;

  factory WebsiteSocialLink.fromJson(Map<String, dynamic> json) =>
      WebsiteSocialLink(
        platform: json['platform'] as String?,
        url: json['url'] as String?,
        icon: json['icon'] as String?,
      );
}

class WebsiteStat {
  const WebsiteStat({this.value, this.label, this.icon});

  final String? value;
  final String? label;
  final String? icon;

  factory WebsiteStat.fromJson(Map<String, dynamic> json) => WebsiteStat(
        value: json['value'] as String?,
        label: json['label'] as String?,
        icon: json['icon'] as String?,
      );
}

/// The whole look-and-feel-plus-copy record behind the site. One row per
/// company; [WebsiteRepository.settings] hands back sensible defaults rather
/// than a 404 when a company has never touched it.
class WebsiteSettings {
  const WebsiteSettings({
    this.companyName,
    this.logoUrl,
    this.faviconUrl,
    this.tagline,
    this.primaryColor,
    this.secondaryColor,
    this.darkMode = false,
    this.heroHeading,
    this.heroSubheading,
    this.heroImageUrl,
    this.heroImages = const [],
    this.aboutText,
    this.mission,
    this.vision,
    this.email,
    this.phone,
    this.address,
    this.mapEmbedUrl,
    this.whatsapp,
    this.socialLinks = const [],
    this.stats = const [],
    this.copyright,
  });

  final String? companyName;
  final String? logoUrl;
  final String? faviconUrl;
  final String? tagline;
  final String? primaryColor;
  final String? secondaryColor;
  final bool darkMode;
  final String? heroHeading;
  final String? heroSubheading;
  final String? heroImageUrl;
  final List<String> heroImages;
  final String? aboutText;
  final String? mission;
  final String? vision;
  final String? email;
  final String? phone;
  final String? address;
  final String? mapEmbedUrl;
  final String? whatsapp;
  final List<WebsiteSocialLink> socialLinks;
  final List<WebsiteStat> stats;
  final String? copyright;

  factory WebsiteSettings.fromJson(Map<String, dynamic> json) =>
      WebsiteSettings(
        companyName: json['companyName'] as String?,
        logoUrl: json['logoUrl'] as String?,
        faviconUrl: json['faviconUrl'] as String?,
        tagline: json['tagline'] as String?,
        primaryColor: json['primaryColor'] as String?,
        secondaryColor: json['secondaryColor'] as String?,
        darkMode: json['darkMode'] as bool? ?? false,
        heroHeading: json['heroHeading'] as String?,
        heroSubheading: json['heroSubheading'] as String?,
        heroImageUrl: json['heroImageUrl'] as String?,
        heroImages: (json['heroImages'] as List<dynamic>?)
                ?.whereType<String>()
                .toList(growable: false) ??
            const [],
        aboutText: json['aboutText'] as String?,
        mission: json['mission'] as String?,
        vision: json['vision'] as String?,
        email: json['email'] as String?,
        phone: json['phone'] as String?,
        address: json['address'] as String?,
        mapEmbedUrl: json['mapEmbedUrl'] as String?,
        whatsapp: json['whatsapp'] as String?,
        socialLinks: (json['socialLinks'] as List<dynamic>?)
                ?.whereType<Map<String, dynamic>>()
                .map(WebsiteSocialLink.fromJson)
                .toList(growable: false) ??
            const [],
        stats: (json['stats'] as List<dynamic>?)
                ?.whereType<Map<String, dynamic>>()
                .map(WebsiteStat.fromJson)
                .toList(growable: false) ??
            const [],
        copyright: json['copyright'] as String?,
      );
}

/// Something the company sells, as the site lists it. Named `Offering`
/// rather than the backend's own `Service` so it cannot be confused with a
/// service request, a catalogue service, or any of this app's other several
/// unrelated "service" concepts.
class WebsiteOffering {
  const WebsiteOffering({
    required this.slug,
    required this.title,
    this.summary,
    this.description,
    this.icon,
    this.imageUrl,
    this.categoryName,
    this.startingPrice,
    this.estimatedTime,
    this.features = const [],
  });

  final String slug;
  final String title;
  final String? summary;
  final String? description;
  final String? icon;
  final String? imageUrl;
  final String? categoryName;
  final String? startingPrice;
  final String? estimatedTime;
  final List<String> features;

  factory WebsiteOffering.fromJson(Map<String, dynamic> json) =>
      WebsiteOffering(
        slug: json['slug'] as String? ?? '',
        title: json['title'] as String? ?? 'Untitled service',
        summary: json['summary'] as String?,
        description: json['description'] as String?,
        icon: json['icon'] as String?,
        imageUrl: json['imageUrl'] as String?,
        categoryName: json['categoryName'] as String?,
        startingPrice: json['startingPrice'] as String?,
        estimatedTime: json['estimatedTime'] as String?,
        features: (json['features'] as List<dynamic>?)
                ?.whereType<String>()
                .toList(growable: false) ??
            const [],
      );
}

/// A blog post or a standalone page — the backend stores both as one entity
/// distinguished by [isPost]; the post-only fields are simply absent on a
/// page.
class WebsiteContent {
  const WebsiteContent({
    required this.slug,
    required this.isPost,
    this.title,
    this.body,
    this.excerpt,
    this.coverImageUrl,
    this.author,
    this.publishedAt,
    this.category,
    this.readMinutes,
  });

  final String slug;
  final bool isPost;
  final String? title;
  final String? body;
  final String? excerpt;
  final String? coverImageUrl;
  final String? author;
  final String? publishedAt;
  final String? category;
  final int? readMinutes;

  factory WebsiteContent.fromJson(Map<String, dynamic> json) =>
      WebsiteContent(
        slug: json['slug'] as String? ?? '',
        isPost: (json['type'] as String?) == 'POST',
        title: json['title'] as String?,
        body: json['body'] as String?,
        excerpt: json['excerpt'] as String?,
        coverImageUrl: json['coverImageUrl'] as String?,
        author: json['author'] as String?,
        publishedAt: json['publishedAt'] as String?,
        category: json['category'] as String?,
        readMinutes: (json['readMinutes'] as num?)?.toInt(),
      );
}

/// A team member or a testimonial — again one backend entity split by
/// [isTestimonial], with each side's fields simply null for the other.
class WebsitePerson {
  const WebsitePerson({
    required this.isTestimonial,
    this.name,
    this.role,
    this.bio,
    this.photoUrl,
    this.company,
    this.quote,
    this.avatarUrl,
    this.rating,
  });

  final bool isTestimonial;
  final String? name;
  final String? role;

  // Team member only.
  final String? bio;
  final String? photoUrl;

  // Testimonial only.
  final String? company;
  final String? quote;
  final String? avatarUrl;
  final int? rating;

  factory WebsitePerson.fromJson(
    Map<String, dynamic> json, {
    required bool isTestimonial,
  }) =>
      WebsitePerson(
        isTestimonial: isTestimonial,
        name: json['name'] as String?,
        role: json['role'] as String?,
        bio: json['bio'] as String?,
        photoUrl: json['photoUrl'] as String?,
        company: json['company'] as String?,
        quote: json['quote'] as String?,
        avatarUrl: json['avatarUrl'] as String?,
        rating: (json['rating'] as num?)?.toInt(),
      );
}

class WebsiteFaq {
  const WebsiteFaq({required this.question, this.answer, this.category});

  final String question;
  final String? answer;
  final String? category;

  factory WebsiteFaq.fromJson(Map<String, dynamic> json) => WebsiteFaq(
        question: json['question'] as String? ?? '',
        answer: json['answer'] as String?,
        category: json['category'] as String?,
      );
}

class WebsiteProject {
  const WebsiteProject({
    required this.title,
    this.summary,
    this.description,
    this.coverImageUrl,
    this.client,
    this.category,
    this.year,
    this.tags = const [],
  });

  final String title;
  final String? summary;
  final String? description;
  final String? coverImageUrl;
  final String? client;
  final String? category;
  final int? year;
  final List<String> tags;

  factory WebsiteProject.fromJson(Map<String, dynamic> json) =>
      WebsiteProject(
        title: json['title'] as String? ?? 'Untitled project',
        summary: json['summary'] as String?,
        description: json['description'] as String?,
        coverImageUrl: json['coverImageUrl'] as String?,
        client: json['client'] as String?,
        category: json['category'] as String?,
        year: (json['year'] as num?)?.toInt(),
        tags: (json['tags'] as List<dynamic>?)
                ?.whereType<String>()
                .toList(growable: false) ??
            const [],
      );
}

class WebsitePricingPlan {
  const WebsitePricingPlan({
    required this.name,
    this.description,
    this.price,
    this.period,
    this.cta,
    this.featured = false,
    this.features = const [],
  });

  final String name;
  final String? description;
  final String? price;
  final String? period;
  final String? cta;
  final bool featured;
  final List<String> features;

  factory WebsitePricingPlan.fromJson(Map<String, dynamic> json) =>
      WebsitePricingPlan(
        name: json['name'] as String? ?? 'Plan',
        description: json['description'] as String?,
        price: json['price'] as String?,
        period: json['period'] as String?,
        cta: json['cta'] as String?,
        featured: json['featured'] as bool? ?? false,
        features: (json['features'] as List<dynamic>?)
                ?.whereType<String>()
                .toList(growable: false) ??
            const [],
      );
}

/// What tracking a submitted request by its code returns.
class WebsiteServiceRequestStatus {
  const WebsiteServiceRequestStatus({
    required this.code,
    required this.status,
    this.serviceTitle,
    this.createdAt,
  });

  final String code;
  final String status;
  final String? serviceTitle;
  final String? createdAt;

  factory WebsiteServiceRequestStatus.fromJson(Map<String, dynamic> json) =>
      WebsiteServiceRequestStatus(
        code: json['code'] as String? ?? '',
        status: json['status'] as String? ?? 'SUBMITTED',
        serviceTitle: json['serviceTitle'] as String?,
        createdAt: json['createdAt'] as String?,
      );
}

// ── Visitor actions — the only writes this module has ──────────────────

class WebsiteContactRequest {
  const WebsiteContactRequest({
    required this.name,
    required this.email,
    this.phone,
    this.subject,
    required this.message,
  });

  final String name;
  final String email;
  final String? phone;
  final String? subject;
  final String message;

  Map<String, dynamic> toJson() => {
        'name': name,
        'email': email,
        'phone': phone,
        'subject': subject,
        'message': message,
      };
}

class WebsiteNewsletterRequest {
  const WebsiteNewsletterRequest({required this.email});

  final String email;

  Map<String, dynamic> toJson() => {'email': email};
}

class WebsiteServiceRequestPayload {
  const WebsiteServiceRequestPayload({
    this.serviceId,
    this.serviceTitle,
    required this.name,
    required this.email,
    this.phone,
    this.message,
  });

  final int? serviceId;
  final String? serviceTitle;
  final String name;
  final String email;
  final String? phone;
  final String? message;

  Map<String, dynamic> toJson() => {
        'serviceId': serviceId,
        'serviceTitle': serviceTitle,
        'name': name,
        'email': email,
        'phone': phone,
        'message': message,
      };
}
