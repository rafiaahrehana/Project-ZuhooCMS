/// Salary structure templates: the named recipes a grade's pay is built from,
/// and the extra components bolted onto one person's structure.
library;

/// A reusable recipe — "Software Engineer Grade A" and what that pays.
///
/// Applying one stamps its numbers onto an employee's own structure; the
/// template itself is untouched afterwards, so changing a template does not
/// change anybody's pay.
class SalaryTemplate {
  const SalaryTemplate({
    required this.id,
    required this.structureName,
    required this.basicPercentage,
    required this.hraPercentage,
    required this.medicalAmount,
    required this.transportAmount,
    required this.internetAmount,
    required this.mobileAmount,
    required this.mealAmount,
    required this.active,
    this.defaultGross,
  });

  final int id;
  final String structureName;

  /// What the grade pays. Choosing a template fills the gross from here and
  /// everything else derives from it.
  final double? defaultGross;

  /// A percentage of gross.
  final double basicPercentage;

  /// A percentage of **basic**, not of gross.
  final double hraPercentage;

  final double medicalAmount;
  final double transportAmount;
  final double internetAmount;
  final double mobileAmount;
  final double mealAmount;
  final bool active;

  factory SalaryTemplate.fromJson(Map<String, dynamic> json) {
    double number(String key) => (json[key] as num?)?.toDouble() ?? 0;

    return SalaryTemplate(
      id: (json['id'] as num?)?.toInt() ?? 0,
      structureName: json['structureName'] as String? ?? '',
      defaultGross: (json['defaultGross'] as num?)?.toDouble(),
      basicPercentage: number('basicPercentage'),
      hraPercentage: number('hraPercentage'),
      medicalAmount: number('medicalAmount'),
      transportAmount: number('transportAmount'),
      internetAmount: number('internetAmount'),
      mobileAmount: number('mobileAmount'),
      mealAmount: number('mealAmount'),
      active: json['active'] as bool? ?? true,
    );
  }
}

/// Saving a template. Create and edit share one endpoint and one shape.
///
/// Every figure is required here because `saveTemplate` assigns all of them
/// and runs each through `nz(...)`, which turns a null into zero. Leaving one
/// out of an edit does not preserve it — it zeroes it. Only `active` is
/// genuinely optional, and it is the one field the backend null-checks.
class SalaryTemplateRequest {
  const SalaryTemplateRequest({
    required this.structureName,
    required this.basicPercentage,
    required this.hraPercentage,
    required this.medicalAmount,
    required this.transportAmount,
    required this.internetAmount,
    required this.mobileAmount,
    required this.mealAmount,
    this.defaultGross,
    this.active,
  });

  final String structureName;
  final double? defaultGross;
  final double basicPercentage;
  final double hraPercentage;
  final double medicalAmount;
  final double transportAmount;
  final double internetAmount;
  final double mobileAmount;
  final double mealAmount;
  final bool? active;

  factory SalaryTemplateRequest.from(SalaryTemplate template) =>
      SalaryTemplateRequest(
        structureName: template.structureName,
        defaultGross: template.defaultGross,
        basicPercentage: template.basicPercentage,
        hraPercentage: template.hraPercentage,
        medicalAmount: template.medicalAmount,
        transportAmount: template.transportAmount,
        internetAmount: template.internetAmount,
        mobileAmount: template.mobileAmount,
        mealAmount: template.mealAmount,
        active: template.active,
      );

  Map<String, dynamic> toJson() => {
        'structureName': structureName,
        'defaultGross': defaultGross,
        'basicPercentage': basicPercentage,
        'hraPercentage': hraPercentage,
        'medicalAmount': medicalAmount,
        'transportAmount': transportAmount,
        'internetAmount': internetAmount,
        'mobileAmount': mobileAmount,
        'mealAmount': mealAmount,
        if (active != null) 'active': active,
      };
}

/// What a template pays out at a given gross.
///
/// Worked out server-side rather than here so the two never disagree. It comes
/// back as a plain map of name to figure, in the order the backend built it.
///
/// One thing to know before reading it: the backend subtracts only basic, HRA,
/// medical, transport and meal from gross when working out the special
/// allowance — internet and mobile are returned but not deducted. So the parts
/// can add up to more than the gross, and [overrun] says by how much rather
/// than hiding it.
class SalaryBreakdown {
  const SalaryBreakdown(this.lines);

  final Map<String, double> lines;

  double get gross => lines['grossSalary'] ?? 0;

  double get total =>
      lines.entries
          .where((entry) => entry.key != 'grossSalary')
          .fold<double>(0, (sum, entry) => sum + entry.value);

  /// How much the parts exceed the gross, or zero when they do not.
  double get overrun {
    final difference = total - gross;
    return difference > 0.005 ? difference : 0;
  }

  factory SalaryBreakdown.fromJson(Map<String, dynamic> json) =>
      SalaryBreakdown({
        for (final entry in json.entries)
          if (entry.value is num) entry.key: (entry.value as num).toDouble(),
      });
}

/// A component bolted onto one employee's structure on top of the recipe.
class StructureExtra {
  const StructureExtra({
    required this.id,
    required this.componentId,
    required this.amount,
    this.componentName,
    this.type,
  });

  final int id;
  final int componentId;
  final double amount;
  final String? componentName;

  /// EARNING, DEDUCTION or EMPLOYER_CONTRIBUTION, from the component itself.
  final String? type;

  factory StructureExtra.fromJson(Map<String, dynamic> json) => StructureExtra(
        id: (json['id'] as num?)?.toInt() ?? 0,
        componentId: (json['componentId'] as num?)?.toInt() ?? 0,
        amount: (json['amount'] as num?)?.toDouble() ?? 0,
        componentName: json['componentName'] as String?,
        type: json['type'] as String?,
      );
}

/// Setting the extras on a structure.
///
/// A whole-list replace, not an append: `setExtras` deletes every extra on the
/// structure and writes back exactly what it is sent. Sending one line leaves
/// one line, and sending an empty list clears them all.
class StructureExtraLine {
  const StructureExtraLine({required this.componentId, required this.amount});

  final int componentId;
  final double amount;

  factory StructureExtraLine.from(StructureExtra extra) => StructureExtraLine(
        componentId: extra.componentId,
        amount: extra.amount,
      );

  Map<String, dynamic> toJson() => {
        'componentId': componentId,
        'amount': amount,
      };
}
