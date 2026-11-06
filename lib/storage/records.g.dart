// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'records.dart';

// **************************************************************************
// IsarCollectionGenerator
// **************************************************************************

// coverage:ignore-file
// ignore_for_file: duplicate_ignore, non_constant_identifier_names, constant_identifier_names, invalid_use_of_protected_member, unnecessary_cast, prefer_const_constructors, lines_longer_than_80_chars, require_trailing_commas, inference_failure_on_function_invocation, unnecessary_parenthesis, unnecessary_raw_strings, unnecessary_null_checks, join_return_with_assignment, prefer_final_locals, avoid_js_rounded_ints, avoid_positional_boolean_parameters, always_specify_types, experimental_member_use

extension GetAppSettingsCollection on Isar {
  IsarCollection<AppSettings> get appSettings => this.collection();
}

const AppSettingsSchema = CollectionSchema(
  name: r'AppSettings',
  id: -5633561779022347008,
  properties: {
    r'createdAt': PropertySchema(
      id: 0,
      name: r'createdAt',
      type: IsarType.long,
    ),
    r'dataRevision': PropertySchema(
      id: 1,
      name: r'dataRevision',
      type: IsarType.long,
    ),
    r'lastSuccessfulOpenAt': PropertySchema(
      id: 2,
      name: r'lastSuccessfulOpenAt',
      type: IsarType.long,
    ),
    r'logicalFormat': PropertySchema(
      id: 3,
      name: r'logicalFormat',
      type: IsarType.long,
    ),
    r'mcpEnabled': PropertySchema(
      id: 4,
      name: r'mcpEnabled',
      type: IsarType.bool,
    ),
    r'profilesListRevision': PropertySchema(
      id: 5,
      name: r'profilesListRevision',
      type: IsarType.long,
    ),
    r'settingsRevision': PropertySchema(
      id: 6,
      name: r'settingsRevision',
      type: IsarType.long,
    ),
    r'terminalConfiguration': PropertySchema(
      id: 7,
      name: r'terminalConfiguration',
      type: IsarType.string,
    ),
    r'theme': PropertySchema(id: 8, name: r'theme', type: IsarType.string),
  },

  estimateSize: _appSettingsEstimateSize,
  serialize: _appSettingsSerialize,
  deserialize: _appSettingsDeserialize,
  deserializeProp: _appSettingsDeserializeProp,
  idName: r'id',
  indexes: {},
  links: {},
  embeddedSchemas: {},

  getId: _appSettingsGetId,
  getLinks: _appSettingsGetLinks,
  attach: _appSettingsAttach,
  version: '3.4.1',
);

int _appSettingsEstimateSize(
  AppSettings object,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  var bytesCount = offsets.last;
  {
    final value = object.terminalConfiguration;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  bytesCount += 3 + object.theme.length * 3;
  return bytesCount;
}

void _appSettingsSerialize(
  AppSettings object,
  IsarWriter writer,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  writer.writeLong(offsets[0], object.createdAt);
  writer.writeLong(offsets[1], object.dataRevision);
  writer.writeLong(offsets[2], object.lastSuccessfulOpenAt);
  writer.writeLong(offsets[3], object.logicalFormat);
  writer.writeBool(offsets[4], object.mcpEnabled);
  writer.writeLong(offsets[5], object.profilesListRevision);
  writer.writeLong(offsets[6], object.settingsRevision);
  writer.writeString(offsets[7], object.terminalConfiguration);
  writer.writeString(offsets[8], object.theme);
}

AppSettings _appSettingsDeserialize(
  Id id,
  IsarReader reader,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  final object = AppSettings();
  object.createdAt = reader.readLong(offsets[0]);
  object.dataRevision = reader.readLong(offsets[1]);
  object.id = id;
  object.lastSuccessfulOpenAt = reader.readLong(offsets[2]);
  object.logicalFormat = reader.readLong(offsets[3]);
  object.mcpEnabled = reader.readBool(offsets[4]);
  object.profilesListRevision = reader.readLong(offsets[5]);
  object.settingsRevision = reader.readLong(offsets[6]);
  object.terminalConfiguration = reader.readStringOrNull(offsets[7]);
  object.theme = reader.readString(offsets[8]);
  return object;
}

P _appSettingsDeserializeProp<P>(
  IsarReader reader,
  int propertyId,
  int offset,
  Map<Type, List<int>> allOffsets,
) {
  switch (propertyId) {
    case 0:
      return (reader.readLong(offset)) as P;
    case 1:
      return (reader.readLong(offset)) as P;
    case 2:
      return (reader.readLong(offset)) as P;
    case 3:
      return (reader.readLong(offset)) as P;
    case 4:
      return (reader.readBool(offset)) as P;
    case 5:
      return (reader.readLong(offset)) as P;
    case 6:
      return (reader.readLong(offset)) as P;
    case 7:
      return (reader.readStringOrNull(offset)) as P;
    case 8:
      return (reader.readString(offset)) as P;
    default:
      throw IsarError('Unknown property with id $propertyId');
  }
}

Id _appSettingsGetId(AppSettings object) {
  return object.id;
}

List<IsarLinkBase<dynamic>> _appSettingsGetLinks(AppSettings object) {
  return [];
}

void _appSettingsAttach(
  IsarCollection<dynamic> col,
  Id id,
  AppSettings object,
) {
  object.id = id;
}

extension AppSettingsQueryWhereSort
    on QueryBuilder<AppSettings, AppSettings, QWhere> {
  QueryBuilder<AppSettings, AppSettings, QAfterWhere> anyId() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(const IdWhereClause.any());
    });
  }
}

extension AppSettingsQueryWhere
    on QueryBuilder<AppSettings, AppSettings, QWhereClause> {
  QueryBuilder<AppSettings, AppSettings, QAfterWhereClause> idEqualTo(Id id) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IdWhereClause.between(lower: id, upper: id));
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterWhereClause> idNotEqualTo(
    Id id,
  ) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(
              IdWhereClause.lessThan(upper: id, includeUpper: false),
            )
            .addWhereClause(
              IdWhereClause.greaterThan(lower: id, includeLower: false),
            );
      } else {
        return query
            .addWhereClause(
              IdWhereClause.greaterThan(lower: id, includeLower: false),
            )
            .addWhereClause(
              IdWhereClause.lessThan(upper: id, includeUpper: false),
            );
      }
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterWhereClause> idGreaterThan(
    Id id, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.greaterThan(lower: id, includeLower: include),
      );
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterWhereClause> idLessThan(
    Id id, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.lessThan(upper: id, includeUpper: include),
      );
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterWhereClause> idBetween(
    Id lowerId,
    Id upperId, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.between(
          lower: lowerId,
          includeLower: includeLower,
          upper: upperId,
          includeUpper: includeUpper,
        ),
      );
    });
  }
}

extension AppSettingsQueryFilter
    on QueryBuilder<AppSettings, AppSettings, QFilterCondition> {
  QueryBuilder<AppSettings, AppSettings, QAfterFilterCondition>
  createdAtEqualTo(int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'createdAt', value: value),
      );
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterFilterCondition>
  createdAtGreaterThan(int value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'createdAt',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterFilterCondition>
  createdAtLessThan(int value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'createdAt',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterFilterCondition>
  createdAtBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'createdAt',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
        ),
      );
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterFilterCondition>
  dataRevisionEqualTo(int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'dataRevision', value: value),
      );
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterFilterCondition>
  dataRevisionGreaterThan(int value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'dataRevision',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterFilterCondition>
  dataRevisionLessThan(int value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'dataRevision',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterFilterCondition>
  dataRevisionBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'dataRevision',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
        ),
      );
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterFilterCondition> idEqualTo(
    Id value,
  ) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'id', value: value),
      );
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterFilterCondition> idGreaterThan(
    Id value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'id',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterFilterCondition> idLessThan(
    Id value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'id',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterFilterCondition> idBetween(
    Id lower,
    Id upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'id',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
        ),
      );
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterFilterCondition>
  lastSuccessfulOpenAtEqualTo(int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'lastSuccessfulOpenAt',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterFilterCondition>
  lastSuccessfulOpenAtGreaterThan(int value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'lastSuccessfulOpenAt',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterFilterCondition>
  lastSuccessfulOpenAtLessThan(int value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'lastSuccessfulOpenAt',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterFilterCondition>
  lastSuccessfulOpenAtBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'lastSuccessfulOpenAt',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
        ),
      );
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterFilterCondition>
  logicalFormatEqualTo(int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'logicalFormat', value: value),
      );
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterFilterCondition>
  logicalFormatGreaterThan(int value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'logicalFormat',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterFilterCondition>
  logicalFormatLessThan(int value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'logicalFormat',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterFilterCondition>
  logicalFormatBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'logicalFormat',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
        ),
      );
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterFilterCondition>
  mcpEnabledEqualTo(bool value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'mcpEnabled', value: value),
      );
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterFilterCondition>
  profilesListRevisionEqualTo(int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'profilesListRevision',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterFilterCondition>
  profilesListRevisionGreaterThan(int value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'profilesListRevision',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterFilterCondition>
  profilesListRevisionLessThan(int value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'profilesListRevision',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterFilterCondition>
  profilesListRevisionBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'profilesListRevision',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
        ),
      );
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterFilterCondition>
  settingsRevisionEqualTo(int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'settingsRevision', value: value),
      );
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterFilterCondition>
  settingsRevisionGreaterThan(int value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'settingsRevision',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterFilterCondition>
  settingsRevisionLessThan(int value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'settingsRevision',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterFilterCondition>
  settingsRevisionBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'settingsRevision',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
        ),
      );
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterFilterCondition>
  terminalConfigurationIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNull(property: r'terminalConfiguration'),
      );
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterFilterCondition>
  terminalConfigurationIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNotNull(property: r'terminalConfiguration'),
      );
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterFilterCondition>
  terminalConfigurationEqualTo(String? value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'terminalConfiguration',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterFilterCondition>
  terminalConfigurationGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'terminalConfiguration',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterFilterCondition>
  terminalConfigurationLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'terminalConfiguration',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterFilterCondition>
  terminalConfigurationBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'terminalConfiguration',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterFilterCondition>
  terminalConfigurationStartsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.startsWith(
          property: r'terminalConfiguration',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterFilterCondition>
  terminalConfigurationEndsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.endsWith(
          property: r'terminalConfiguration',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterFilterCondition>
  terminalConfigurationContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.contains(
          property: r'terminalConfiguration',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterFilterCondition>
  terminalConfigurationMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.matches(
          property: r'terminalConfiguration',
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterFilterCondition>
  terminalConfigurationIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'terminalConfiguration', value: ''),
      );
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterFilterCondition>
  terminalConfigurationIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          property: r'terminalConfiguration',
          value: '',
        ),
      );
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterFilterCondition> themeEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'theme',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterFilterCondition>
  themeGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'theme',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterFilterCondition> themeLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'theme',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterFilterCondition> themeBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'theme',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterFilterCondition> themeStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.startsWith(
          property: r'theme',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterFilterCondition> themeEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.endsWith(
          property: r'theme',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterFilterCondition> themeContains(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.contains(
          property: r'theme',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterFilterCondition> themeMatches(
    String pattern, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.matches(
          property: r'theme',
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterFilterCondition> themeIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'theme', value: ''),
      );
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterFilterCondition>
  themeIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(property: r'theme', value: ''),
      );
    });
  }
}

extension AppSettingsQueryObject
    on QueryBuilder<AppSettings, AppSettings, QFilterCondition> {}

extension AppSettingsQueryLinks
    on QueryBuilder<AppSettings, AppSettings, QFilterCondition> {}

extension AppSettingsQuerySortBy
    on QueryBuilder<AppSettings, AppSettings, QSortBy> {
  QueryBuilder<AppSettings, AppSettings, QAfterSortBy> sortByCreatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'createdAt', Sort.asc);
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterSortBy> sortByCreatedAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'createdAt', Sort.desc);
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterSortBy> sortByDataRevision() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'dataRevision', Sort.asc);
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterSortBy>
  sortByDataRevisionDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'dataRevision', Sort.desc);
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterSortBy>
  sortByLastSuccessfulOpenAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lastSuccessfulOpenAt', Sort.asc);
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterSortBy>
  sortByLastSuccessfulOpenAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lastSuccessfulOpenAt', Sort.desc);
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterSortBy> sortByLogicalFormat() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'logicalFormat', Sort.asc);
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterSortBy>
  sortByLogicalFormatDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'logicalFormat', Sort.desc);
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterSortBy> sortByMcpEnabled() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'mcpEnabled', Sort.asc);
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterSortBy> sortByMcpEnabledDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'mcpEnabled', Sort.desc);
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterSortBy>
  sortByProfilesListRevision() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'profilesListRevision', Sort.asc);
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterSortBy>
  sortByProfilesListRevisionDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'profilesListRevision', Sort.desc);
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterSortBy>
  sortBySettingsRevision() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'settingsRevision', Sort.asc);
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterSortBy>
  sortBySettingsRevisionDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'settingsRevision', Sort.desc);
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterSortBy>
  sortByTerminalConfiguration() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'terminalConfiguration', Sort.asc);
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterSortBy>
  sortByTerminalConfigurationDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'terminalConfiguration', Sort.desc);
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterSortBy> sortByTheme() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'theme', Sort.asc);
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterSortBy> sortByThemeDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'theme', Sort.desc);
    });
  }
}

extension AppSettingsQuerySortThenBy
    on QueryBuilder<AppSettings, AppSettings, QSortThenBy> {
  QueryBuilder<AppSettings, AppSettings, QAfterSortBy> thenByCreatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'createdAt', Sort.asc);
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterSortBy> thenByCreatedAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'createdAt', Sort.desc);
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterSortBy> thenByDataRevision() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'dataRevision', Sort.asc);
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterSortBy>
  thenByDataRevisionDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'dataRevision', Sort.desc);
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterSortBy> thenById() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.asc);
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterSortBy> thenByIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.desc);
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterSortBy>
  thenByLastSuccessfulOpenAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lastSuccessfulOpenAt', Sort.asc);
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterSortBy>
  thenByLastSuccessfulOpenAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lastSuccessfulOpenAt', Sort.desc);
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterSortBy> thenByLogicalFormat() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'logicalFormat', Sort.asc);
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterSortBy>
  thenByLogicalFormatDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'logicalFormat', Sort.desc);
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterSortBy> thenByMcpEnabled() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'mcpEnabled', Sort.asc);
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterSortBy> thenByMcpEnabledDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'mcpEnabled', Sort.desc);
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterSortBy>
  thenByProfilesListRevision() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'profilesListRevision', Sort.asc);
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterSortBy>
  thenByProfilesListRevisionDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'profilesListRevision', Sort.desc);
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterSortBy>
  thenBySettingsRevision() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'settingsRevision', Sort.asc);
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterSortBy>
  thenBySettingsRevisionDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'settingsRevision', Sort.desc);
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterSortBy>
  thenByTerminalConfiguration() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'terminalConfiguration', Sort.asc);
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterSortBy>
  thenByTerminalConfigurationDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'terminalConfiguration', Sort.desc);
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterSortBy> thenByTheme() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'theme', Sort.asc);
    });
  }

  QueryBuilder<AppSettings, AppSettings, QAfterSortBy> thenByThemeDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'theme', Sort.desc);
    });
  }
}

extension AppSettingsQueryWhereDistinct
    on QueryBuilder<AppSettings, AppSettings, QDistinct> {
  QueryBuilder<AppSettings, AppSettings, QDistinct> distinctByCreatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'createdAt');
    });
  }

  QueryBuilder<AppSettings, AppSettings, QDistinct> distinctByDataRevision() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'dataRevision');
    });
  }

  QueryBuilder<AppSettings, AppSettings, QDistinct>
  distinctByLastSuccessfulOpenAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'lastSuccessfulOpenAt');
    });
  }

  QueryBuilder<AppSettings, AppSettings, QDistinct> distinctByLogicalFormat() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'logicalFormat');
    });
  }

  QueryBuilder<AppSettings, AppSettings, QDistinct> distinctByMcpEnabled() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'mcpEnabled');
    });
  }

  QueryBuilder<AppSettings, AppSettings, QDistinct>
  distinctByProfilesListRevision() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'profilesListRevision');
    });
  }

  QueryBuilder<AppSettings, AppSettings, QDistinct>
  distinctBySettingsRevision() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'settingsRevision');
    });
  }

  QueryBuilder<AppSettings, AppSettings, QDistinct>
  distinctByTerminalConfiguration({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(
        r'terminalConfiguration',
        caseSensitive: caseSensitive,
      );
    });
  }

  QueryBuilder<AppSettings, AppSettings, QDistinct> distinctByTheme({
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'theme', caseSensitive: caseSensitive);
    });
  }
}

extension AppSettingsQueryProperty
    on QueryBuilder<AppSettings, AppSettings, QQueryProperty> {
  QueryBuilder<AppSettings, int, QQueryOperations> idProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'id');
    });
  }

  QueryBuilder<AppSettings, int, QQueryOperations> createdAtProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'createdAt');
    });
  }

  QueryBuilder<AppSettings, int, QQueryOperations> dataRevisionProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'dataRevision');
    });
  }

  QueryBuilder<AppSettings, int, QQueryOperations>
  lastSuccessfulOpenAtProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'lastSuccessfulOpenAt');
    });
  }

  QueryBuilder<AppSettings, int, QQueryOperations> logicalFormatProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'logicalFormat');
    });
  }

  QueryBuilder<AppSettings, bool, QQueryOperations> mcpEnabledProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'mcpEnabled');
    });
  }

  QueryBuilder<AppSettings, int, QQueryOperations>
  profilesListRevisionProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'profilesListRevision');
    });
  }

  QueryBuilder<AppSettings, int, QQueryOperations> settingsRevisionProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'settingsRevision');
    });
  }

  QueryBuilder<AppSettings, String?, QQueryOperations>
  terminalConfigurationProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'terminalConfiguration');
    });
  }

  QueryBuilder<AppSettings, String, QQueryOperations> themeProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'theme');
    });
  }
}

// coverage:ignore-file
// ignore_for_file: duplicate_ignore, non_constant_identifier_names, constant_identifier_names, invalid_use_of_protected_member, unnecessary_cast, prefer_const_constructors, lines_longer_than_80_chars, require_trailing_commas, inference_failure_on_function_invocation, unnecessary_parenthesis, unnecessary_raw_strings, unnecessary_null_checks, join_return_with_assignment, prefer_final_locals, avoid_js_rounded_ints, avoid_positional_boolean_parameters, always_specify_types, experimental_member_use

extension GetProfileCollection on Isar {
  IsarCollection<Profile> get profiles => this.collection();
}

const ProfileSchema = CollectionSchema(
  name: r'Profile',
  id: 1266279811925214857,
  properties: {
    r'authKind': PropertySchema(
      id: 0,
      name: r'authKind',
      type: IsarType.string,
    ),
    r'connectionRevision': PropertySchema(
      id: 1,
      name: r'connectionRevision',
      type: IsarType.long,
    ),
    r'createdAt': PropertySchema(
      id: 2,
      name: r'createdAt',
      type: IsarType.long,
    ),
    r'credentialId': PropertySchema(
      id: 3,
      name: r'credentialId',
      type: IsarType.string,
    ),
    r'displayName': PropertySchema(
      id: 4,
      name: r'displayName',
      type: IsarType.string,
    ),
    r'endpointId': PropertySchema(
      id: 5,
      name: r'endpointId',
      type: IsarType.string,
    ),
    r'normalizedHost': PropertySchema(
      id: 6,
      name: r'normalizedHost',
      type: IsarType.string,
    ),
    r'originalHost': PropertySchema(
      id: 7,
      name: r'originalHost',
      type: IsarType.string,
    ),
    r'port': PropertySchema(id: 8, name: r'port', type: IsarType.long),
    r'profileId': PropertySchema(
      id: 9,
      name: r'profileId',
      type: IsarType.string,
    ),
    r'profileRevision': PropertySchema(
      id: 10,
      name: r'profileRevision',
      type: IsarType.long,
    ),
    r'updatedAt': PropertySchema(
      id: 11,
      name: r'updatedAt',
      type: IsarType.long,
    ),
    r'username': PropertySchema(
      id: 12,
      name: r'username',
      type: IsarType.string,
    ),
  },

  estimateSize: _profileEstimateSize,
  serialize: _profileSerialize,
  deserialize: _profileDeserialize,
  deserializeProp: _profileDeserializeProp,
  idName: r'id',
  indexes: {
    r'profileId': IndexSchema(
      id: 6052971939042612300,
      name: r'profileId',
      unique: true,
      replace: false,
      properties: [
        IndexPropertySchema(
          name: r'profileId',
          type: IndexType.hash,
          caseSensitive: true,
        ),
      ],
    ),
    r'endpointId': IndexSchema(
      id: -2131995512278992622,
      name: r'endpointId',
      unique: false,
      replace: false,
      properties: [
        IndexPropertySchema(
          name: r'endpointId',
          type: IndexType.hash,
          caseSensitive: true,
        ),
      ],
    ),
  },
  links: {},
  embeddedSchemas: {},

  getId: _profileGetId,
  getLinks: _profileGetLinks,
  attach: _profileAttach,
  version: '3.4.1',
);

int _profileEstimateSize(
  Profile object,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  var bytesCount = offsets.last;
  bytesCount += 3 + object.authKind.length * 3;
  bytesCount += 3 + object.credentialId.length * 3;
  bytesCount += 3 + object.displayName.length * 3;
  bytesCount += 3 + object.endpointId.length * 3;
  bytesCount += 3 + object.normalizedHost.length * 3;
  bytesCount += 3 + object.originalHost.length * 3;
  bytesCount += 3 + object.profileId.length * 3;
  bytesCount += 3 + object.username.length * 3;
  return bytesCount;
}

void _profileSerialize(
  Profile object,
  IsarWriter writer,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  writer.writeString(offsets[0], object.authKind);
  writer.writeLong(offsets[1], object.connectionRevision);
  writer.writeLong(offsets[2], object.createdAt);
  writer.writeString(offsets[3], object.credentialId);
  writer.writeString(offsets[4], object.displayName);
  writer.writeString(offsets[5], object.endpointId);
  writer.writeString(offsets[6], object.normalizedHost);
  writer.writeString(offsets[7], object.originalHost);
  writer.writeLong(offsets[8], object.port);
  writer.writeString(offsets[9], object.profileId);
  writer.writeLong(offsets[10], object.profileRevision);
  writer.writeLong(offsets[11], object.updatedAt);
  writer.writeString(offsets[12], object.username);
}

Profile _profileDeserialize(
  Id id,
  IsarReader reader,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  final object = Profile();
  object.authKind = reader.readString(offsets[0]);
  object.connectionRevision = reader.readLong(offsets[1]);
  object.createdAt = reader.readLong(offsets[2]);
  object.credentialId = reader.readString(offsets[3]);
  object.displayName = reader.readString(offsets[4]);
  object.endpointId = reader.readString(offsets[5]);
  object.id = id;
  object.normalizedHost = reader.readString(offsets[6]);
  object.originalHost = reader.readString(offsets[7]);
  object.port = reader.readLong(offsets[8]);
  object.profileId = reader.readString(offsets[9]);
  object.profileRevision = reader.readLong(offsets[10]);
  object.updatedAt = reader.readLong(offsets[11]);
  object.username = reader.readString(offsets[12]);
  return object;
}

P _profileDeserializeProp<P>(
  IsarReader reader,
  int propertyId,
  int offset,
  Map<Type, List<int>> allOffsets,
) {
  switch (propertyId) {
    case 0:
      return (reader.readString(offset)) as P;
    case 1:
      return (reader.readLong(offset)) as P;
    case 2:
      return (reader.readLong(offset)) as P;
    case 3:
      return (reader.readString(offset)) as P;
    case 4:
      return (reader.readString(offset)) as P;
    case 5:
      return (reader.readString(offset)) as P;
    case 6:
      return (reader.readString(offset)) as P;
    case 7:
      return (reader.readString(offset)) as P;
    case 8:
      return (reader.readLong(offset)) as P;
    case 9:
      return (reader.readString(offset)) as P;
    case 10:
      return (reader.readLong(offset)) as P;
    case 11:
      return (reader.readLong(offset)) as P;
    case 12:
      return (reader.readString(offset)) as P;
    default:
      throw IsarError('Unknown property with id $propertyId');
  }
}

Id _profileGetId(Profile object) {
  return object.id;
}

List<IsarLinkBase<dynamic>> _profileGetLinks(Profile object) {
  return [];
}

void _profileAttach(IsarCollection<dynamic> col, Id id, Profile object) {
  object.id = id;
}

extension ProfileByIndex on IsarCollection<Profile> {
  Future<Profile?> getByProfileId(String profileId) {
    return getByIndex(r'profileId', [profileId]);
  }

  Profile? getByProfileIdSync(String profileId) {
    return getByIndexSync(r'profileId', [profileId]);
  }

  Future<bool> deleteByProfileId(String profileId) {
    return deleteByIndex(r'profileId', [profileId]);
  }

  bool deleteByProfileIdSync(String profileId) {
    return deleteByIndexSync(r'profileId', [profileId]);
  }

  Future<List<Profile?>> getAllByProfileId(List<String> profileIdValues) {
    final values = profileIdValues.map((e) => [e]).toList();
    return getAllByIndex(r'profileId', values);
  }

  List<Profile?> getAllByProfileIdSync(List<String> profileIdValues) {
    final values = profileIdValues.map((e) => [e]).toList();
    return getAllByIndexSync(r'profileId', values);
  }

  Future<int> deleteAllByProfileId(List<String> profileIdValues) {
    final values = profileIdValues.map((e) => [e]).toList();
    return deleteAllByIndex(r'profileId', values);
  }

  int deleteAllByProfileIdSync(List<String> profileIdValues) {
    final values = profileIdValues.map((e) => [e]).toList();
    return deleteAllByIndexSync(r'profileId', values);
  }

  Future<Id> putByProfileId(Profile object) {
    return putByIndex(r'profileId', object);
  }

  Id putByProfileIdSync(Profile object, {bool saveLinks = true}) {
    return putByIndexSync(r'profileId', object, saveLinks: saveLinks);
  }

  Future<List<Id>> putAllByProfileId(List<Profile> objects) {
    return putAllByIndex(r'profileId', objects);
  }

  List<Id> putAllByProfileIdSync(
    List<Profile> objects, {
    bool saveLinks = true,
  }) {
    return putAllByIndexSync(r'profileId', objects, saveLinks: saveLinks);
  }
}

extension ProfileQueryWhereSort on QueryBuilder<Profile, Profile, QWhere> {
  QueryBuilder<Profile, Profile, QAfterWhere> anyId() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(const IdWhereClause.any());
    });
  }
}

extension ProfileQueryWhere on QueryBuilder<Profile, Profile, QWhereClause> {
  QueryBuilder<Profile, Profile, QAfterWhereClause> idEqualTo(Id id) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IdWhereClause.between(lower: id, upper: id));
    });
  }

  QueryBuilder<Profile, Profile, QAfterWhereClause> idNotEqualTo(Id id) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(
              IdWhereClause.lessThan(upper: id, includeUpper: false),
            )
            .addWhereClause(
              IdWhereClause.greaterThan(lower: id, includeLower: false),
            );
      } else {
        return query
            .addWhereClause(
              IdWhereClause.greaterThan(lower: id, includeLower: false),
            )
            .addWhereClause(
              IdWhereClause.lessThan(upper: id, includeUpper: false),
            );
      }
    });
  }

  QueryBuilder<Profile, Profile, QAfterWhereClause> idGreaterThan(
    Id id, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.greaterThan(lower: id, includeLower: include),
      );
    });
  }

  QueryBuilder<Profile, Profile, QAfterWhereClause> idLessThan(
    Id id, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.lessThan(upper: id, includeUpper: include),
      );
    });
  }

  QueryBuilder<Profile, Profile, QAfterWhereClause> idBetween(
    Id lowerId,
    Id upperId, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.between(
          lower: lowerId,
          includeLower: includeLower,
          upper: upperId,
          includeUpper: includeUpper,
        ),
      );
    });
  }

  QueryBuilder<Profile, Profile, QAfterWhereClause> profileIdEqualTo(
    String profileId,
  ) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IndexWhereClause.equalTo(indexName: r'profileId', value: [profileId]),
      );
    });
  }

  QueryBuilder<Profile, Profile, QAfterWhereClause> profileIdNotEqualTo(
    String profileId,
  ) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'profileId',
                lower: [],
                upper: [profileId],
                includeUpper: false,
              ),
            )
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'profileId',
                lower: [profileId],
                includeLower: false,
                upper: [],
              ),
            );
      } else {
        return query
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'profileId',
                lower: [profileId],
                includeLower: false,
                upper: [],
              ),
            )
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'profileId',
                lower: [],
                upper: [profileId],
                includeUpper: false,
              ),
            );
      }
    });
  }

  QueryBuilder<Profile, Profile, QAfterWhereClause> endpointIdEqualTo(
    String endpointId,
  ) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IndexWhereClause.equalTo(indexName: r'endpointId', value: [endpointId]),
      );
    });
  }

  QueryBuilder<Profile, Profile, QAfterWhereClause> endpointIdNotEqualTo(
    String endpointId,
  ) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'endpointId',
                lower: [],
                upper: [endpointId],
                includeUpper: false,
              ),
            )
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'endpointId',
                lower: [endpointId],
                includeLower: false,
                upper: [],
              ),
            );
      } else {
        return query
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'endpointId',
                lower: [endpointId],
                includeLower: false,
                upper: [],
              ),
            )
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'endpointId',
                lower: [],
                upper: [endpointId],
                includeUpper: false,
              ),
            );
      }
    });
  }
}

extension ProfileQueryFilter
    on QueryBuilder<Profile, Profile, QFilterCondition> {
  QueryBuilder<Profile, Profile, QAfterFilterCondition> authKindEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'authKind',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Profile, Profile, QAfterFilterCondition> authKindGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'authKind',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Profile, Profile, QAfterFilterCondition> authKindLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'authKind',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Profile, Profile, QAfterFilterCondition> authKindBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'authKind',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Profile, Profile, QAfterFilterCondition> authKindStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.startsWith(
          property: r'authKind',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Profile, Profile, QAfterFilterCondition> authKindEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.endsWith(
          property: r'authKind',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Profile, Profile, QAfterFilterCondition> authKindContains(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.contains(
          property: r'authKind',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Profile, Profile, QAfterFilterCondition> authKindMatches(
    String pattern, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.matches(
          property: r'authKind',
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Profile, Profile, QAfterFilterCondition> authKindIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'authKind', value: ''),
      );
    });
  }

  QueryBuilder<Profile, Profile, QAfterFilterCondition> authKindIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(property: r'authKind', value: ''),
      );
    });
  }

  QueryBuilder<Profile, Profile, QAfterFilterCondition>
  connectionRevisionEqualTo(int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'connectionRevision', value: value),
      );
    });
  }

  QueryBuilder<Profile, Profile, QAfterFilterCondition>
  connectionRevisionGreaterThan(int value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'connectionRevision',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<Profile, Profile, QAfterFilterCondition>
  connectionRevisionLessThan(int value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'connectionRevision',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<Profile, Profile, QAfterFilterCondition>
  connectionRevisionBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'connectionRevision',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
        ),
      );
    });
  }

  QueryBuilder<Profile, Profile, QAfterFilterCondition> createdAtEqualTo(
    int value,
  ) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'createdAt', value: value),
      );
    });
  }

  QueryBuilder<Profile, Profile, QAfterFilterCondition> createdAtGreaterThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'createdAt',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<Profile, Profile, QAfterFilterCondition> createdAtLessThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'createdAt',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<Profile, Profile, QAfterFilterCondition> createdAtBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'createdAt',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
        ),
      );
    });
  }

  QueryBuilder<Profile, Profile, QAfterFilterCondition> credentialIdEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'credentialId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Profile, Profile, QAfterFilterCondition> credentialIdGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'credentialId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Profile, Profile, QAfterFilterCondition> credentialIdLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'credentialId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Profile, Profile, QAfterFilterCondition> credentialIdBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'credentialId',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Profile, Profile, QAfterFilterCondition> credentialIdStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.startsWith(
          property: r'credentialId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Profile, Profile, QAfterFilterCondition> credentialIdEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.endsWith(
          property: r'credentialId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Profile, Profile, QAfterFilterCondition> credentialIdContains(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.contains(
          property: r'credentialId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Profile, Profile, QAfterFilterCondition> credentialIdMatches(
    String pattern, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.matches(
          property: r'credentialId',
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Profile, Profile, QAfterFilterCondition> credentialIdIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'credentialId', value: ''),
      );
    });
  }

  QueryBuilder<Profile, Profile, QAfterFilterCondition>
  credentialIdIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(property: r'credentialId', value: ''),
      );
    });
  }

  QueryBuilder<Profile, Profile, QAfterFilterCondition> displayNameEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'displayName',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Profile, Profile, QAfterFilterCondition> displayNameGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'displayName',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Profile, Profile, QAfterFilterCondition> displayNameLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'displayName',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Profile, Profile, QAfterFilterCondition> displayNameBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'displayName',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Profile, Profile, QAfterFilterCondition> displayNameStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.startsWith(
          property: r'displayName',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Profile, Profile, QAfterFilterCondition> displayNameEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.endsWith(
          property: r'displayName',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Profile, Profile, QAfterFilterCondition> displayNameContains(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.contains(
          property: r'displayName',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Profile, Profile, QAfterFilterCondition> displayNameMatches(
    String pattern, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.matches(
          property: r'displayName',
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Profile, Profile, QAfterFilterCondition> displayNameIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'displayName', value: ''),
      );
    });
  }

  QueryBuilder<Profile, Profile, QAfterFilterCondition>
  displayNameIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(property: r'displayName', value: ''),
      );
    });
  }

  QueryBuilder<Profile, Profile, QAfterFilterCondition> endpointIdEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'endpointId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Profile, Profile, QAfterFilterCondition> endpointIdGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'endpointId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Profile, Profile, QAfterFilterCondition> endpointIdLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'endpointId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Profile, Profile, QAfterFilterCondition> endpointIdBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'endpointId',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Profile, Profile, QAfterFilterCondition> endpointIdStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.startsWith(
          property: r'endpointId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Profile, Profile, QAfterFilterCondition> endpointIdEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.endsWith(
          property: r'endpointId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Profile, Profile, QAfterFilterCondition> endpointIdContains(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.contains(
          property: r'endpointId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Profile, Profile, QAfterFilterCondition> endpointIdMatches(
    String pattern, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.matches(
          property: r'endpointId',
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Profile, Profile, QAfterFilterCondition> endpointIdIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'endpointId', value: ''),
      );
    });
  }

  QueryBuilder<Profile, Profile, QAfterFilterCondition> endpointIdIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(property: r'endpointId', value: ''),
      );
    });
  }

  QueryBuilder<Profile, Profile, QAfterFilterCondition> idEqualTo(Id value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'id', value: value),
      );
    });
  }

  QueryBuilder<Profile, Profile, QAfterFilterCondition> idGreaterThan(
    Id value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'id',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<Profile, Profile, QAfterFilterCondition> idLessThan(
    Id value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'id',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<Profile, Profile, QAfterFilterCondition> idBetween(
    Id lower,
    Id upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'id',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
        ),
      );
    });
  }

  QueryBuilder<Profile, Profile, QAfterFilterCondition> normalizedHostEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'normalizedHost',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Profile, Profile, QAfterFilterCondition>
  normalizedHostGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'normalizedHost',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Profile, Profile, QAfterFilterCondition> normalizedHostLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'normalizedHost',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Profile, Profile, QAfterFilterCondition> normalizedHostBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'normalizedHost',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Profile, Profile, QAfterFilterCondition>
  normalizedHostStartsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.startsWith(
          property: r'normalizedHost',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Profile, Profile, QAfterFilterCondition> normalizedHostEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.endsWith(
          property: r'normalizedHost',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Profile, Profile, QAfterFilterCondition> normalizedHostContains(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.contains(
          property: r'normalizedHost',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Profile, Profile, QAfterFilterCondition> normalizedHostMatches(
    String pattern, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.matches(
          property: r'normalizedHost',
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Profile, Profile, QAfterFilterCondition>
  normalizedHostIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'normalizedHost', value: ''),
      );
    });
  }

  QueryBuilder<Profile, Profile, QAfterFilterCondition>
  normalizedHostIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(property: r'normalizedHost', value: ''),
      );
    });
  }

  QueryBuilder<Profile, Profile, QAfterFilterCondition> originalHostEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'originalHost',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Profile, Profile, QAfterFilterCondition> originalHostGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'originalHost',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Profile, Profile, QAfterFilterCondition> originalHostLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'originalHost',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Profile, Profile, QAfterFilterCondition> originalHostBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'originalHost',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Profile, Profile, QAfterFilterCondition> originalHostStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.startsWith(
          property: r'originalHost',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Profile, Profile, QAfterFilterCondition> originalHostEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.endsWith(
          property: r'originalHost',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Profile, Profile, QAfterFilterCondition> originalHostContains(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.contains(
          property: r'originalHost',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Profile, Profile, QAfterFilterCondition> originalHostMatches(
    String pattern, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.matches(
          property: r'originalHost',
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Profile, Profile, QAfterFilterCondition> originalHostIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'originalHost', value: ''),
      );
    });
  }

  QueryBuilder<Profile, Profile, QAfterFilterCondition>
  originalHostIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(property: r'originalHost', value: ''),
      );
    });
  }

  QueryBuilder<Profile, Profile, QAfterFilterCondition> portEqualTo(int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'port', value: value),
      );
    });
  }

  QueryBuilder<Profile, Profile, QAfterFilterCondition> portGreaterThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'port',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<Profile, Profile, QAfterFilterCondition> portLessThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'port',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<Profile, Profile, QAfterFilterCondition> portBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'port',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
        ),
      );
    });
  }

  QueryBuilder<Profile, Profile, QAfterFilterCondition> profileIdEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'profileId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Profile, Profile, QAfterFilterCondition> profileIdGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'profileId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Profile, Profile, QAfterFilterCondition> profileIdLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'profileId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Profile, Profile, QAfterFilterCondition> profileIdBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'profileId',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Profile, Profile, QAfterFilterCondition> profileIdStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.startsWith(
          property: r'profileId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Profile, Profile, QAfterFilterCondition> profileIdEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.endsWith(
          property: r'profileId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Profile, Profile, QAfterFilterCondition> profileIdContains(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.contains(
          property: r'profileId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Profile, Profile, QAfterFilterCondition> profileIdMatches(
    String pattern, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.matches(
          property: r'profileId',
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Profile, Profile, QAfterFilterCondition> profileIdIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'profileId', value: ''),
      );
    });
  }

  QueryBuilder<Profile, Profile, QAfterFilterCondition> profileIdIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(property: r'profileId', value: ''),
      );
    });
  }

  QueryBuilder<Profile, Profile, QAfterFilterCondition> profileRevisionEqualTo(
    int value,
  ) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'profileRevision', value: value),
      );
    });
  }

  QueryBuilder<Profile, Profile, QAfterFilterCondition>
  profileRevisionGreaterThan(int value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'profileRevision',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<Profile, Profile, QAfterFilterCondition> profileRevisionLessThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'profileRevision',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<Profile, Profile, QAfterFilterCondition> profileRevisionBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'profileRevision',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
        ),
      );
    });
  }

  QueryBuilder<Profile, Profile, QAfterFilterCondition> updatedAtEqualTo(
    int value,
  ) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'updatedAt', value: value),
      );
    });
  }

  QueryBuilder<Profile, Profile, QAfterFilterCondition> updatedAtGreaterThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'updatedAt',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<Profile, Profile, QAfterFilterCondition> updatedAtLessThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'updatedAt',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<Profile, Profile, QAfterFilterCondition> updatedAtBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'updatedAt',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
        ),
      );
    });
  }

  QueryBuilder<Profile, Profile, QAfterFilterCondition> usernameEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'username',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Profile, Profile, QAfterFilterCondition> usernameGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'username',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Profile, Profile, QAfterFilterCondition> usernameLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'username',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Profile, Profile, QAfterFilterCondition> usernameBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'username',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Profile, Profile, QAfterFilterCondition> usernameStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.startsWith(
          property: r'username',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Profile, Profile, QAfterFilterCondition> usernameEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.endsWith(
          property: r'username',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Profile, Profile, QAfterFilterCondition> usernameContains(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.contains(
          property: r'username',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Profile, Profile, QAfterFilterCondition> usernameMatches(
    String pattern, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.matches(
          property: r'username',
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Profile, Profile, QAfterFilterCondition> usernameIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'username', value: ''),
      );
    });
  }

  QueryBuilder<Profile, Profile, QAfterFilterCondition> usernameIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(property: r'username', value: ''),
      );
    });
  }
}

extension ProfileQueryObject
    on QueryBuilder<Profile, Profile, QFilterCondition> {}

extension ProfileQueryLinks
    on QueryBuilder<Profile, Profile, QFilterCondition> {}

extension ProfileQuerySortBy on QueryBuilder<Profile, Profile, QSortBy> {
  QueryBuilder<Profile, Profile, QAfterSortBy> sortByAuthKind() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'authKind', Sort.asc);
    });
  }

  QueryBuilder<Profile, Profile, QAfterSortBy> sortByAuthKindDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'authKind', Sort.desc);
    });
  }

  QueryBuilder<Profile, Profile, QAfterSortBy> sortByConnectionRevision() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'connectionRevision', Sort.asc);
    });
  }

  QueryBuilder<Profile, Profile, QAfterSortBy> sortByConnectionRevisionDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'connectionRevision', Sort.desc);
    });
  }

  QueryBuilder<Profile, Profile, QAfterSortBy> sortByCreatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'createdAt', Sort.asc);
    });
  }

  QueryBuilder<Profile, Profile, QAfterSortBy> sortByCreatedAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'createdAt', Sort.desc);
    });
  }

  QueryBuilder<Profile, Profile, QAfterSortBy> sortByCredentialId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'credentialId', Sort.asc);
    });
  }

  QueryBuilder<Profile, Profile, QAfterSortBy> sortByCredentialIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'credentialId', Sort.desc);
    });
  }

  QueryBuilder<Profile, Profile, QAfterSortBy> sortByDisplayName() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'displayName', Sort.asc);
    });
  }

  QueryBuilder<Profile, Profile, QAfterSortBy> sortByDisplayNameDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'displayName', Sort.desc);
    });
  }

  QueryBuilder<Profile, Profile, QAfterSortBy> sortByEndpointId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'endpointId', Sort.asc);
    });
  }

  QueryBuilder<Profile, Profile, QAfterSortBy> sortByEndpointIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'endpointId', Sort.desc);
    });
  }

  QueryBuilder<Profile, Profile, QAfterSortBy> sortByNormalizedHost() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'normalizedHost', Sort.asc);
    });
  }

  QueryBuilder<Profile, Profile, QAfterSortBy> sortByNormalizedHostDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'normalizedHost', Sort.desc);
    });
  }

  QueryBuilder<Profile, Profile, QAfterSortBy> sortByOriginalHost() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'originalHost', Sort.asc);
    });
  }

  QueryBuilder<Profile, Profile, QAfterSortBy> sortByOriginalHostDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'originalHost', Sort.desc);
    });
  }

  QueryBuilder<Profile, Profile, QAfterSortBy> sortByPort() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'port', Sort.asc);
    });
  }

  QueryBuilder<Profile, Profile, QAfterSortBy> sortByPortDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'port', Sort.desc);
    });
  }

  QueryBuilder<Profile, Profile, QAfterSortBy> sortByProfileId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'profileId', Sort.asc);
    });
  }

  QueryBuilder<Profile, Profile, QAfterSortBy> sortByProfileIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'profileId', Sort.desc);
    });
  }

  QueryBuilder<Profile, Profile, QAfterSortBy> sortByProfileRevision() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'profileRevision', Sort.asc);
    });
  }

  QueryBuilder<Profile, Profile, QAfterSortBy> sortByProfileRevisionDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'profileRevision', Sort.desc);
    });
  }

  QueryBuilder<Profile, Profile, QAfterSortBy> sortByUpdatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'updatedAt', Sort.asc);
    });
  }

  QueryBuilder<Profile, Profile, QAfterSortBy> sortByUpdatedAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'updatedAt', Sort.desc);
    });
  }

  QueryBuilder<Profile, Profile, QAfterSortBy> sortByUsername() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'username', Sort.asc);
    });
  }

  QueryBuilder<Profile, Profile, QAfterSortBy> sortByUsernameDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'username', Sort.desc);
    });
  }
}

extension ProfileQuerySortThenBy
    on QueryBuilder<Profile, Profile, QSortThenBy> {
  QueryBuilder<Profile, Profile, QAfterSortBy> thenByAuthKind() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'authKind', Sort.asc);
    });
  }

  QueryBuilder<Profile, Profile, QAfterSortBy> thenByAuthKindDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'authKind', Sort.desc);
    });
  }

  QueryBuilder<Profile, Profile, QAfterSortBy> thenByConnectionRevision() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'connectionRevision', Sort.asc);
    });
  }

  QueryBuilder<Profile, Profile, QAfterSortBy> thenByConnectionRevisionDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'connectionRevision', Sort.desc);
    });
  }

  QueryBuilder<Profile, Profile, QAfterSortBy> thenByCreatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'createdAt', Sort.asc);
    });
  }

  QueryBuilder<Profile, Profile, QAfterSortBy> thenByCreatedAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'createdAt', Sort.desc);
    });
  }

  QueryBuilder<Profile, Profile, QAfterSortBy> thenByCredentialId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'credentialId', Sort.asc);
    });
  }

  QueryBuilder<Profile, Profile, QAfterSortBy> thenByCredentialIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'credentialId', Sort.desc);
    });
  }

  QueryBuilder<Profile, Profile, QAfterSortBy> thenByDisplayName() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'displayName', Sort.asc);
    });
  }

  QueryBuilder<Profile, Profile, QAfterSortBy> thenByDisplayNameDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'displayName', Sort.desc);
    });
  }

  QueryBuilder<Profile, Profile, QAfterSortBy> thenByEndpointId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'endpointId', Sort.asc);
    });
  }

  QueryBuilder<Profile, Profile, QAfterSortBy> thenByEndpointIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'endpointId', Sort.desc);
    });
  }

  QueryBuilder<Profile, Profile, QAfterSortBy> thenById() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.asc);
    });
  }

  QueryBuilder<Profile, Profile, QAfterSortBy> thenByIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.desc);
    });
  }

  QueryBuilder<Profile, Profile, QAfterSortBy> thenByNormalizedHost() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'normalizedHost', Sort.asc);
    });
  }

  QueryBuilder<Profile, Profile, QAfterSortBy> thenByNormalizedHostDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'normalizedHost', Sort.desc);
    });
  }

  QueryBuilder<Profile, Profile, QAfterSortBy> thenByOriginalHost() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'originalHost', Sort.asc);
    });
  }

  QueryBuilder<Profile, Profile, QAfterSortBy> thenByOriginalHostDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'originalHost', Sort.desc);
    });
  }

  QueryBuilder<Profile, Profile, QAfterSortBy> thenByPort() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'port', Sort.asc);
    });
  }

  QueryBuilder<Profile, Profile, QAfterSortBy> thenByPortDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'port', Sort.desc);
    });
  }

  QueryBuilder<Profile, Profile, QAfterSortBy> thenByProfileId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'profileId', Sort.asc);
    });
  }

  QueryBuilder<Profile, Profile, QAfterSortBy> thenByProfileIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'profileId', Sort.desc);
    });
  }

  QueryBuilder<Profile, Profile, QAfterSortBy> thenByProfileRevision() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'profileRevision', Sort.asc);
    });
  }

  QueryBuilder<Profile, Profile, QAfterSortBy> thenByProfileRevisionDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'profileRevision', Sort.desc);
    });
  }

  QueryBuilder<Profile, Profile, QAfterSortBy> thenByUpdatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'updatedAt', Sort.asc);
    });
  }

  QueryBuilder<Profile, Profile, QAfterSortBy> thenByUpdatedAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'updatedAt', Sort.desc);
    });
  }

  QueryBuilder<Profile, Profile, QAfterSortBy> thenByUsername() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'username', Sort.asc);
    });
  }

  QueryBuilder<Profile, Profile, QAfterSortBy> thenByUsernameDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'username', Sort.desc);
    });
  }
}

extension ProfileQueryWhereDistinct
    on QueryBuilder<Profile, Profile, QDistinct> {
  QueryBuilder<Profile, Profile, QDistinct> distinctByAuthKind({
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'authKind', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<Profile, Profile, QDistinct> distinctByConnectionRevision() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'connectionRevision');
    });
  }

  QueryBuilder<Profile, Profile, QDistinct> distinctByCreatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'createdAt');
    });
  }

  QueryBuilder<Profile, Profile, QDistinct> distinctByCredentialId({
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'credentialId', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<Profile, Profile, QDistinct> distinctByDisplayName({
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'displayName', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<Profile, Profile, QDistinct> distinctByEndpointId({
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'endpointId', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<Profile, Profile, QDistinct> distinctByNormalizedHost({
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(
        r'normalizedHost',
        caseSensitive: caseSensitive,
      );
    });
  }

  QueryBuilder<Profile, Profile, QDistinct> distinctByOriginalHost({
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'originalHost', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<Profile, Profile, QDistinct> distinctByPort() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'port');
    });
  }

  QueryBuilder<Profile, Profile, QDistinct> distinctByProfileId({
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'profileId', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<Profile, Profile, QDistinct> distinctByProfileRevision() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'profileRevision');
    });
  }

  QueryBuilder<Profile, Profile, QDistinct> distinctByUpdatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'updatedAt');
    });
  }

  QueryBuilder<Profile, Profile, QDistinct> distinctByUsername({
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'username', caseSensitive: caseSensitive);
    });
  }
}

extension ProfileQueryProperty
    on QueryBuilder<Profile, Profile, QQueryProperty> {
  QueryBuilder<Profile, int, QQueryOperations> idProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'id');
    });
  }

  QueryBuilder<Profile, String, QQueryOperations> authKindProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'authKind');
    });
  }

  QueryBuilder<Profile, int, QQueryOperations> connectionRevisionProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'connectionRevision');
    });
  }

  QueryBuilder<Profile, int, QQueryOperations> createdAtProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'createdAt');
    });
  }

  QueryBuilder<Profile, String, QQueryOperations> credentialIdProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'credentialId');
    });
  }

  QueryBuilder<Profile, String, QQueryOperations> displayNameProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'displayName');
    });
  }

  QueryBuilder<Profile, String, QQueryOperations> endpointIdProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'endpointId');
    });
  }

  QueryBuilder<Profile, String, QQueryOperations> normalizedHostProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'normalizedHost');
    });
  }

  QueryBuilder<Profile, String, QQueryOperations> originalHostProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'originalHost');
    });
  }

  QueryBuilder<Profile, int, QQueryOperations> portProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'port');
    });
  }

  QueryBuilder<Profile, String, QQueryOperations> profileIdProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'profileId');
    });
  }

  QueryBuilder<Profile, int, QQueryOperations> profileRevisionProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'profileRevision');
    });
  }

  QueryBuilder<Profile, int, QQueryOperations> updatedAtProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'updatedAt');
    });
  }

  QueryBuilder<Profile, String, QQueryOperations> usernameProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'username');
    });
  }
}

// coverage:ignore-file
// ignore_for_file: duplicate_ignore, non_constant_identifier_names, constant_identifier_names, invalid_use_of_protected_member, unnecessary_cast, prefer_const_constructors, lines_longer_than_80_chars, require_trailing_commas, inference_failure_on_function_invocation, unnecessary_parenthesis, unnecessary_raw_strings, unnecessary_null_checks, join_return_with_assignment, prefer_final_locals, avoid_js_rounded_ints, avoid_positional_boolean_parameters, always_specify_types, experimental_member_use

extension GetCredentialCollection on Isar {
  IsarCollection<Credential> get credentials => this.collection();
}

const CredentialSchema = CollectionSchema(
  name: r'Credential',
  id: 8105671720389824406,
  properties: {
    r'credentialId': PropertySchema(
      id: 0,
      name: r'credentialId',
      type: IsarType.string,
    ),
    r'kind': PropertySchema(id: 1, name: r'kind', type: IsarType.string),
    r'profileId': PropertySchema(
      id: 2,
      name: r'profileId',
      type: IsarType.string,
    ),
    r'protectedBytes': PropertySchema(
      id: 3,
      name: r'protectedBytes',
      type: IsarType.byteList,
    ),
    r'publicKeyBits': PropertySchema(
      id: 4,
      name: r'publicKeyBits',
      type: IsarType.long,
    ),
    r'publicKeyBytes': PropertySchema(
      id: 5,
      name: r'publicKeyBytes',
      type: IsarType.byteList,
    ),
    r'publicKeyType': PropertySchema(
      id: 6,
      name: r'publicKeyType',
      type: IsarType.string,
    ),
    r'secretRevision': PropertySchema(
      id: 7,
      name: r'secretRevision',
      type: IsarType.long,
    ),
  },

  estimateSize: _credentialEstimateSize,
  serialize: _credentialSerialize,
  deserialize: _credentialDeserialize,
  deserializeProp: _credentialDeserializeProp,
  idName: r'id',
  indexes: {
    r'credentialId': IndexSchema(
      id: 7147664887779844858,
      name: r'credentialId',
      unique: true,
      replace: false,
      properties: [
        IndexPropertySchema(
          name: r'credentialId',
          type: IndexType.hash,
          caseSensitive: true,
        ),
      ],
    ),
    r'profileId': IndexSchema(
      id: 6052971939042612300,
      name: r'profileId',
      unique: true,
      replace: false,
      properties: [
        IndexPropertySchema(
          name: r'profileId',
          type: IndexType.hash,
          caseSensitive: true,
        ),
      ],
    ),
  },
  links: {},
  embeddedSchemas: {},

  getId: _credentialGetId,
  getLinks: _credentialGetLinks,
  attach: _credentialAttach,
  version: '3.4.1',
);

int _credentialEstimateSize(
  Credential object,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  var bytesCount = offsets.last;
  bytesCount += 3 + object.credentialId.length * 3;
  bytesCount += 3 + object.kind.length * 3;
  bytesCount += 3 + object.profileId.length * 3;
  bytesCount += 3 + object.protectedBytes.length;
  {
    final value = object.publicKeyBytes;
    if (value != null) {
      bytesCount += 3 + value.length;
    }
  }
  {
    final value = object.publicKeyType;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  return bytesCount;
}

void _credentialSerialize(
  Credential object,
  IsarWriter writer,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  writer.writeString(offsets[0], object.credentialId);
  writer.writeString(offsets[1], object.kind);
  writer.writeString(offsets[2], object.profileId);
  writer.writeByteList(offsets[3], object.protectedBytes);
  writer.writeLong(offsets[4], object.publicKeyBits);
  writer.writeByteList(offsets[5], object.publicKeyBytes);
  writer.writeString(offsets[6], object.publicKeyType);
  writer.writeLong(offsets[7], object.secretRevision);
}

Credential _credentialDeserialize(
  Id id,
  IsarReader reader,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  final object = Credential();
  object.credentialId = reader.readString(offsets[0]);
  object.id = id;
  object.kind = reader.readString(offsets[1]);
  object.profileId = reader.readString(offsets[2]);
  object.protectedBytes = reader.readByteList(offsets[3]) ?? [];
  object.publicKeyBits = reader.readLongOrNull(offsets[4]);
  object.publicKeyBytes = reader.readByteList(offsets[5]);
  object.publicKeyType = reader.readStringOrNull(offsets[6]);
  object.secretRevision = reader.readLong(offsets[7]);
  return object;
}

P _credentialDeserializeProp<P>(
  IsarReader reader,
  int propertyId,
  int offset,
  Map<Type, List<int>> allOffsets,
) {
  switch (propertyId) {
    case 0:
      return (reader.readString(offset)) as P;
    case 1:
      return (reader.readString(offset)) as P;
    case 2:
      return (reader.readString(offset)) as P;
    case 3:
      return (reader.readByteList(offset) ?? []) as P;
    case 4:
      return (reader.readLongOrNull(offset)) as P;
    case 5:
      return (reader.readByteList(offset)) as P;
    case 6:
      return (reader.readStringOrNull(offset)) as P;
    case 7:
      return (reader.readLong(offset)) as P;
    default:
      throw IsarError('Unknown property with id $propertyId');
  }
}

Id _credentialGetId(Credential object) {
  return object.id;
}

List<IsarLinkBase<dynamic>> _credentialGetLinks(Credential object) {
  return [];
}

void _credentialAttach(IsarCollection<dynamic> col, Id id, Credential object) {
  object.id = id;
}

extension CredentialByIndex on IsarCollection<Credential> {
  Future<Credential?> getByCredentialId(String credentialId) {
    return getByIndex(r'credentialId', [credentialId]);
  }

  Credential? getByCredentialIdSync(String credentialId) {
    return getByIndexSync(r'credentialId', [credentialId]);
  }

  Future<bool> deleteByCredentialId(String credentialId) {
    return deleteByIndex(r'credentialId', [credentialId]);
  }

  bool deleteByCredentialIdSync(String credentialId) {
    return deleteByIndexSync(r'credentialId', [credentialId]);
  }

  Future<List<Credential?>> getAllByCredentialId(
    List<String> credentialIdValues,
  ) {
    final values = credentialIdValues.map((e) => [e]).toList();
    return getAllByIndex(r'credentialId', values);
  }

  List<Credential?> getAllByCredentialIdSync(List<String> credentialIdValues) {
    final values = credentialIdValues.map((e) => [e]).toList();
    return getAllByIndexSync(r'credentialId', values);
  }

  Future<int> deleteAllByCredentialId(List<String> credentialIdValues) {
    final values = credentialIdValues.map((e) => [e]).toList();
    return deleteAllByIndex(r'credentialId', values);
  }

  int deleteAllByCredentialIdSync(List<String> credentialIdValues) {
    final values = credentialIdValues.map((e) => [e]).toList();
    return deleteAllByIndexSync(r'credentialId', values);
  }

  Future<Id> putByCredentialId(Credential object) {
    return putByIndex(r'credentialId', object);
  }

  Id putByCredentialIdSync(Credential object, {bool saveLinks = true}) {
    return putByIndexSync(r'credentialId', object, saveLinks: saveLinks);
  }

  Future<List<Id>> putAllByCredentialId(List<Credential> objects) {
    return putAllByIndex(r'credentialId', objects);
  }

  List<Id> putAllByCredentialIdSync(
    List<Credential> objects, {
    bool saveLinks = true,
  }) {
    return putAllByIndexSync(r'credentialId', objects, saveLinks: saveLinks);
  }

  Future<Credential?> getByProfileId(String profileId) {
    return getByIndex(r'profileId', [profileId]);
  }

  Credential? getByProfileIdSync(String profileId) {
    return getByIndexSync(r'profileId', [profileId]);
  }

  Future<bool> deleteByProfileId(String profileId) {
    return deleteByIndex(r'profileId', [profileId]);
  }

  bool deleteByProfileIdSync(String profileId) {
    return deleteByIndexSync(r'profileId', [profileId]);
  }

  Future<List<Credential?>> getAllByProfileId(List<String> profileIdValues) {
    final values = profileIdValues.map((e) => [e]).toList();
    return getAllByIndex(r'profileId', values);
  }

  List<Credential?> getAllByProfileIdSync(List<String> profileIdValues) {
    final values = profileIdValues.map((e) => [e]).toList();
    return getAllByIndexSync(r'profileId', values);
  }

  Future<int> deleteAllByProfileId(List<String> profileIdValues) {
    final values = profileIdValues.map((e) => [e]).toList();
    return deleteAllByIndex(r'profileId', values);
  }

  int deleteAllByProfileIdSync(List<String> profileIdValues) {
    final values = profileIdValues.map((e) => [e]).toList();
    return deleteAllByIndexSync(r'profileId', values);
  }

  Future<Id> putByProfileId(Credential object) {
    return putByIndex(r'profileId', object);
  }

  Id putByProfileIdSync(Credential object, {bool saveLinks = true}) {
    return putByIndexSync(r'profileId', object, saveLinks: saveLinks);
  }

  Future<List<Id>> putAllByProfileId(List<Credential> objects) {
    return putAllByIndex(r'profileId', objects);
  }

  List<Id> putAllByProfileIdSync(
    List<Credential> objects, {
    bool saveLinks = true,
  }) {
    return putAllByIndexSync(r'profileId', objects, saveLinks: saveLinks);
  }
}

extension CredentialQueryWhereSort
    on QueryBuilder<Credential, Credential, QWhere> {
  QueryBuilder<Credential, Credential, QAfterWhere> anyId() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(const IdWhereClause.any());
    });
  }
}

extension CredentialQueryWhere
    on QueryBuilder<Credential, Credential, QWhereClause> {
  QueryBuilder<Credential, Credential, QAfterWhereClause> idEqualTo(Id id) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IdWhereClause.between(lower: id, upper: id));
    });
  }

  QueryBuilder<Credential, Credential, QAfterWhereClause> idNotEqualTo(Id id) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(
              IdWhereClause.lessThan(upper: id, includeUpper: false),
            )
            .addWhereClause(
              IdWhereClause.greaterThan(lower: id, includeLower: false),
            );
      } else {
        return query
            .addWhereClause(
              IdWhereClause.greaterThan(lower: id, includeLower: false),
            )
            .addWhereClause(
              IdWhereClause.lessThan(upper: id, includeUpper: false),
            );
      }
    });
  }

  QueryBuilder<Credential, Credential, QAfterWhereClause> idGreaterThan(
    Id id, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.greaterThan(lower: id, includeLower: include),
      );
    });
  }

  QueryBuilder<Credential, Credential, QAfterWhereClause> idLessThan(
    Id id, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.lessThan(upper: id, includeUpper: include),
      );
    });
  }

  QueryBuilder<Credential, Credential, QAfterWhereClause> idBetween(
    Id lowerId,
    Id upperId, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.between(
          lower: lowerId,
          includeLower: includeLower,
          upper: upperId,
          includeUpper: includeUpper,
        ),
      );
    });
  }

  QueryBuilder<Credential, Credential, QAfterWhereClause> credentialIdEqualTo(
    String credentialId,
  ) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IndexWhereClause.equalTo(
          indexName: r'credentialId',
          value: [credentialId],
        ),
      );
    });
  }

  QueryBuilder<Credential, Credential, QAfterWhereClause>
  credentialIdNotEqualTo(String credentialId) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'credentialId',
                lower: [],
                upper: [credentialId],
                includeUpper: false,
              ),
            )
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'credentialId',
                lower: [credentialId],
                includeLower: false,
                upper: [],
              ),
            );
      } else {
        return query
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'credentialId',
                lower: [credentialId],
                includeLower: false,
                upper: [],
              ),
            )
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'credentialId',
                lower: [],
                upper: [credentialId],
                includeUpper: false,
              ),
            );
      }
    });
  }

  QueryBuilder<Credential, Credential, QAfterWhereClause> profileIdEqualTo(
    String profileId,
  ) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IndexWhereClause.equalTo(indexName: r'profileId', value: [profileId]),
      );
    });
  }

  QueryBuilder<Credential, Credential, QAfterWhereClause> profileIdNotEqualTo(
    String profileId,
  ) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'profileId',
                lower: [],
                upper: [profileId],
                includeUpper: false,
              ),
            )
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'profileId',
                lower: [profileId],
                includeLower: false,
                upper: [],
              ),
            );
      } else {
        return query
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'profileId',
                lower: [profileId],
                includeLower: false,
                upper: [],
              ),
            )
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'profileId',
                lower: [],
                upper: [profileId],
                includeUpper: false,
              ),
            );
      }
    });
  }
}

extension CredentialQueryFilter
    on QueryBuilder<Credential, Credential, QFilterCondition> {
  QueryBuilder<Credential, Credential, QAfterFilterCondition>
  credentialIdEqualTo(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'credentialId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Credential, Credential, QAfterFilterCondition>
  credentialIdGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'credentialId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Credential, Credential, QAfterFilterCondition>
  credentialIdLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'credentialId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Credential, Credential, QAfterFilterCondition>
  credentialIdBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'credentialId',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Credential, Credential, QAfterFilterCondition>
  credentialIdStartsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.startsWith(
          property: r'credentialId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Credential, Credential, QAfterFilterCondition>
  credentialIdEndsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.endsWith(
          property: r'credentialId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Credential, Credential, QAfterFilterCondition>
  credentialIdContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.contains(
          property: r'credentialId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Credential, Credential, QAfterFilterCondition>
  credentialIdMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.matches(
          property: r'credentialId',
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Credential, Credential, QAfterFilterCondition>
  credentialIdIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'credentialId', value: ''),
      );
    });
  }

  QueryBuilder<Credential, Credential, QAfterFilterCondition>
  credentialIdIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(property: r'credentialId', value: ''),
      );
    });
  }

  QueryBuilder<Credential, Credential, QAfterFilterCondition> idEqualTo(
    Id value,
  ) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'id', value: value),
      );
    });
  }

  QueryBuilder<Credential, Credential, QAfterFilterCondition> idGreaterThan(
    Id value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'id',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<Credential, Credential, QAfterFilterCondition> idLessThan(
    Id value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'id',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<Credential, Credential, QAfterFilterCondition> idBetween(
    Id lower,
    Id upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'id',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
        ),
      );
    });
  }

  QueryBuilder<Credential, Credential, QAfterFilterCondition> kindEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'kind',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Credential, Credential, QAfterFilterCondition> kindGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'kind',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Credential, Credential, QAfterFilterCondition> kindLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'kind',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Credential, Credential, QAfterFilterCondition> kindBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'kind',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Credential, Credential, QAfterFilterCondition> kindStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.startsWith(
          property: r'kind',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Credential, Credential, QAfterFilterCondition> kindEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.endsWith(
          property: r'kind',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Credential, Credential, QAfterFilterCondition> kindContains(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.contains(
          property: r'kind',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Credential, Credential, QAfterFilterCondition> kindMatches(
    String pattern, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.matches(
          property: r'kind',
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Credential, Credential, QAfterFilterCondition> kindIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'kind', value: ''),
      );
    });
  }

  QueryBuilder<Credential, Credential, QAfterFilterCondition> kindIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(property: r'kind', value: ''),
      );
    });
  }

  QueryBuilder<Credential, Credential, QAfterFilterCondition> profileIdEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'profileId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Credential, Credential, QAfterFilterCondition>
  profileIdGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'profileId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Credential, Credential, QAfterFilterCondition> profileIdLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'profileId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Credential, Credential, QAfterFilterCondition> profileIdBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'profileId',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Credential, Credential, QAfterFilterCondition>
  profileIdStartsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.startsWith(
          property: r'profileId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Credential, Credential, QAfterFilterCondition> profileIdEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.endsWith(
          property: r'profileId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Credential, Credential, QAfterFilterCondition> profileIdContains(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.contains(
          property: r'profileId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Credential, Credential, QAfterFilterCondition> profileIdMatches(
    String pattern, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.matches(
          property: r'profileId',
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Credential, Credential, QAfterFilterCondition>
  profileIdIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'profileId', value: ''),
      );
    });
  }

  QueryBuilder<Credential, Credential, QAfterFilterCondition>
  profileIdIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(property: r'profileId', value: ''),
      );
    });
  }

  QueryBuilder<Credential, Credential, QAfterFilterCondition>
  protectedBytesElementEqualTo(int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'protectedBytes', value: value),
      );
    });
  }

  QueryBuilder<Credential, Credential, QAfterFilterCondition>
  protectedBytesElementGreaterThan(int value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'protectedBytes',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<Credential, Credential, QAfterFilterCondition>
  protectedBytesElementLessThan(int value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'protectedBytes',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<Credential, Credential, QAfterFilterCondition>
  protectedBytesElementBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'protectedBytes',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
        ),
      );
    });
  }

  QueryBuilder<Credential, Credential, QAfterFilterCondition>
  protectedBytesLengthEqualTo(int length) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(r'protectedBytes', length, true, length, true);
    });
  }

  QueryBuilder<Credential, Credential, QAfterFilterCondition>
  protectedBytesIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(r'protectedBytes', 0, true, 0, true);
    });
  }

  QueryBuilder<Credential, Credential, QAfterFilterCondition>
  protectedBytesIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(r'protectedBytes', 0, false, 999999, true);
    });
  }

  QueryBuilder<Credential, Credential, QAfterFilterCondition>
  protectedBytesLengthLessThan(int length, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(r'protectedBytes', 0, true, length, include);
    });
  }

  QueryBuilder<Credential, Credential, QAfterFilterCondition>
  protectedBytesLengthGreaterThan(int length, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(r'protectedBytes', length, include, 999999, true);
    });
  }

  QueryBuilder<Credential, Credential, QAfterFilterCondition>
  protectedBytesLengthBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'protectedBytes',
        lower,
        includeLower,
        upper,
        includeUpper,
      );
    });
  }

  QueryBuilder<Credential, Credential, QAfterFilterCondition>
  publicKeyBitsIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNull(property: r'publicKeyBits'),
      );
    });
  }

  QueryBuilder<Credential, Credential, QAfterFilterCondition>
  publicKeyBitsIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNotNull(property: r'publicKeyBits'),
      );
    });
  }

  QueryBuilder<Credential, Credential, QAfterFilterCondition>
  publicKeyBitsEqualTo(int? value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'publicKeyBits', value: value),
      );
    });
  }

  QueryBuilder<Credential, Credential, QAfterFilterCondition>
  publicKeyBitsGreaterThan(int? value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'publicKeyBits',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<Credential, Credential, QAfterFilterCondition>
  publicKeyBitsLessThan(int? value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'publicKeyBits',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<Credential, Credential, QAfterFilterCondition>
  publicKeyBitsBetween(
    int? lower,
    int? upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'publicKeyBits',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
        ),
      );
    });
  }

  QueryBuilder<Credential, Credential, QAfterFilterCondition>
  publicKeyBytesIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNull(property: r'publicKeyBytes'),
      );
    });
  }

  QueryBuilder<Credential, Credential, QAfterFilterCondition>
  publicKeyBytesIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNotNull(property: r'publicKeyBytes'),
      );
    });
  }

  QueryBuilder<Credential, Credential, QAfterFilterCondition>
  publicKeyBytesElementEqualTo(int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'publicKeyBytes', value: value),
      );
    });
  }

  QueryBuilder<Credential, Credential, QAfterFilterCondition>
  publicKeyBytesElementGreaterThan(int value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'publicKeyBytes',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<Credential, Credential, QAfterFilterCondition>
  publicKeyBytesElementLessThan(int value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'publicKeyBytes',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<Credential, Credential, QAfterFilterCondition>
  publicKeyBytesElementBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'publicKeyBytes',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
        ),
      );
    });
  }

  QueryBuilder<Credential, Credential, QAfterFilterCondition>
  publicKeyBytesLengthEqualTo(int length) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(r'publicKeyBytes', length, true, length, true);
    });
  }

  QueryBuilder<Credential, Credential, QAfterFilterCondition>
  publicKeyBytesIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(r'publicKeyBytes', 0, true, 0, true);
    });
  }

  QueryBuilder<Credential, Credential, QAfterFilterCondition>
  publicKeyBytesIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(r'publicKeyBytes', 0, false, 999999, true);
    });
  }

  QueryBuilder<Credential, Credential, QAfterFilterCondition>
  publicKeyBytesLengthLessThan(int length, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(r'publicKeyBytes', 0, true, length, include);
    });
  }

  QueryBuilder<Credential, Credential, QAfterFilterCondition>
  publicKeyBytesLengthGreaterThan(int length, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(r'publicKeyBytes', length, include, 999999, true);
    });
  }

  QueryBuilder<Credential, Credential, QAfterFilterCondition>
  publicKeyBytesLengthBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'publicKeyBytes',
        lower,
        includeLower,
        upper,
        includeUpper,
      );
    });
  }

  QueryBuilder<Credential, Credential, QAfterFilterCondition>
  publicKeyTypeIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNull(property: r'publicKeyType'),
      );
    });
  }

  QueryBuilder<Credential, Credential, QAfterFilterCondition>
  publicKeyTypeIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNotNull(property: r'publicKeyType'),
      );
    });
  }

  QueryBuilder<Credential, Credential, QAfterFilterCondition>
  publicKeyTypeEqualTo(String? value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'publicKeyType',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Credential, Credential, QAfterFilterCondition>
  publicKeyTypeGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'publicKeyType',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Credential, Credential, QAfterFilterCondition>
  publicKeyTypeLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'publicKeyType',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Credential, Credential, QAfterFilterCondition>
  publicKeyTypeBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'publicKeyType',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Credential, Credential, QAfterFilterCondition>
  publicKeyTypeStartsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.startsWith(
          property: r'publicKeyType',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Credential, Credential, QAfterFilterCondition>
  publicKeyTypeEndsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.endsWith(
          property: r'publicKeyType',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Credential, Credential, QAfterFilterCondition>
  publicKeyTypeContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.contains(
          property: r'publicKeyType',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Credential, Credential, QAfterFilterCondition>
  publicKeyTypeMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.matches(
          property: r'publicKeyType',
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<Credential, Credential, QAfterFilterCondition>
  publicKeyTypeIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'publicKeyType', value: ''),
      );
    });
  }

  QueryBuilder<Credential, Credential, QAfterFilterCondition>
  publicKeyTypeIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(property: r'publicKeyType', value: ''),
      );
    });
  }

  QueryBuilder<Credential, Credential, QAfterFilterCondition>
  secretRevisionEqualTo(int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'secretRevision', value: value),
      );
    });
  }

  QueryBuilder<Credential, Credential, QAfterFilterCondition>
  secretRevisionGreaterThan(int value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'secretRevision',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<Credential, Credential, QAfterFilterCondition>
  secretRevisionLessThan(int value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'secretRevision',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<Credential, Credential, QAfterFilterCondition>
  secretRevisionBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'secretRevision',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
        ),
      );
    });
  }
}

extension CredentialQueryObject
    on QueryBuilder<Credential, Credential, QFilterCondition> {}

extension CredentialQueryLinks
    on QueryBuilder<Credential, Credential, QFilterCondition> {}

extension CredentialQuerySortBy
    on QueryBuilder<Credential, Credential, QSortBy> {
  QueryBuilder<Credential, Credential, QAfterSortBy> sortByCredentialId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'credentialId', Sort.asc);
    });
  }

  QueryBuilder<Credential, Credential, QAfterSortBy> sortByCredentialIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'credentialId', Sort.desc);
    });
  }

  QueryBuilder<Credential, Credential, QAfterSortBy> sortByKind() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'kind', Sort.asc);
    });
  }

  QueryBuilder<Credential, Credential, QAfterSortBy> sortByKindDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'kind', Sort.desc);
    });
  }

  QueryBuilder<Credential, Credential, QAfterSortBy> sortByProfileId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'profileId', Sort.asc);
    });
  }

  QueryBuilder<Credential, Credential, QAfterSortBy> sortByProfileIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'profileId', Sort.desc);
    });
  }

  QueryBuilder<Credential, Credential, QAfterSortBy> sortByPublicKeyBits() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'publicKeyBits', Sort.asc);
    });
  }

  QueryBuilder<Credential, Credential, QAfterSortBy> sortByPublicKeyBitsDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'publicKeyBits', Sort.desc);
    });
  }

  QueryBuilder<Credential, Credential, QAfterSortBy> sortByPublicKeyType() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'publicKeyType', Sort.asc);
    });
  }

  QueryBuilder<Credential, Credential, QAfterSortBy> sortByPublicKeyTypeDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'publicKeyType', Sort.desc);
    });
  }

  QueryBuilder<Credential, Credential, QAfterSortBy> sortBySecretRevision() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'secretRevision', Sort.asc);
    });
  }

  QueryBuilder<Credential, Credential, QAfterSortBy>
  sortBySecretRevisionDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'secretRevision', Sort.desc);
    });
  }
}

extension CredentialQuerySortThenBy
    on QueryBuilder<Credential, Credential, QSortThenBy> {
  QueryBuilder<Credential, Credential, QAfterSortBy> thenByCredentialId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'credentialId', Sort.asc);
    });
  }

  QueryBuilder<Credential, Credential, QAfterSortBy> thenByCredentialIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'credentialId', Sort.desc);
    });
  }

  QueryBuilder<Credential, Credential, QAfterSortBy> thenById() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.asc);
    });
  }

  QueryBuilder<Credential, Credential, QAfterSortBy> thenByIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.desc);
    });
  }

  QueryBuilder<Credential, Credential, QAfterSortBy> thenByKind() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'kind', Sort.asc);
    });
  }

  QueryBuilder<Credential, Credential, QAfterSortBy> thenByKindDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'kind', Sort.desc);
    });
  }

  QueryBuilder<Credential, Credential, QAfterSortBy> thenByProfileId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'profileId', Sort.asc);
    });
  }

  QueryBuilder<Credential, Credential, QAfterSortBy> thenByProfileIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'profileId', Sort.desc);
    });
  }

  QueryBuilder<Credential, Credential, QAfterSortBy> thenByPublicKeyBits() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'publicKeyBits', Sort.asc);
    });
  }

  QueryBuilder<Credential, Credential, QAfterSortBy> thenByPublicKeyBitsDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'publicKeyBits', Sort.desc);
    });
  }

  QueryBuilder<Credential, Credential, QAfterSortBy> thenByPublicKeyType() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'publicKeyType', Sort.asc);
    });
  }

  QueryBuilder<Credential, Credential, QAfterSortBy> thenByPublicKeyTypeDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'publicKeyType', Sort.desc);
    });
  }

  QueryBuilder<Credential, Credential, QAfterSortBy> thenBySecretRevision() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'secretRevision', Sort.asc);
    });
  }

  QueryBuilder<Credential, Credential, QAfterSortBy>
  thenBySecretRevisionDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'secretRevision', Sort.desc);
    });
  }
}

extension CredentialQueryWhereDistinct
    on QueryBuilder<Credential, Credential, QDistinct> {
  QueryBuilder<Credential, Credential, QDistinct> distinctByCredentialId({
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'credentialId', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<Credential, Credential, QDistinct> distinctByKind({
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'kind', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<Credential, Credential, QDistinct> distinctByProfileId({
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'profileId', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<Credential, Credential, QDistinct> distinctByProtectedBytes() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'protectedBytes');
    });
  }

  QueryBuilder<Credential, Credential, QDistinct> distinctByPublicKeyBits() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'publicKeyBits');
    });
  }

  QueryBuilder<Credential, Credential, QDistinct> distinctByPublicKeyBytes() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'publicKeyBytes');
    });
  }

  QueryBuilder<Credential, Credential, QDistinct> distinctByPublicKeyType({
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(
        r'publicKeyType',
        caseSensitive: caseSensitive,
      );
    });
  }

  QueryBuilder<Credential, Credential, QDistinct> distinctBySecretRevision() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'secretRevision');
    });
  }
}

extension CredentialQueryProperty
    on QueryBuilder<Credential, Credential, QQueryProperty> {
  QueryBuilder<Credential, int, QQueryOperations> idProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'id');
    });
  }

  QueryBuilder<Credential, String, QQueryOperations> credentialIdProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'credentialId');
    });
  }

  QueryBuilder<Credential, String, QQueryOperations> kindProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'kind');
    });
  }

  QueryBuilder<Credential, String, QQueryOperations> profileIdProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'profileId');
    });
  }

  QueryBuilder<Credential, List<int>, QQueryOperations>
  protectedBytesProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'protectedBytes');
    });
  }

  QueryBuilder<Credential, int?, QQueryOperations> publicKeyBitsProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'publicKeyBits');
    });
  }

  QueryBuilder<Credential, List<int>?, QQueryOperations>
  publicKeyBytesProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'publicKeyBytes');
    });
  }

  QueryBuilder<Credential, String?, QQueryOperations> publicKeyTypeProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'publicKeyType');
    });
  }

  QueryBuilder<Credential, int, QQueryOperations> secretRevisionProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'secretRevision');
    });
  }
}

// coverage:ignore-file
// ignore_for_file: duplicate_ignore, non_constant_identifier_names, constant_identifier_names, invalid_use_of_protected_member, unnecessary_cast, prefer_const_constructors, lines_longer_than_80_chars, require_trailing_commas, inference_failure_on_function_invocation, unnecessary_parenthesis, unnecessary_raw_strings, unnecessary_null_checks, join_return_with_assignment, prefer_final_locals, avoid_js_rounded_ints, avoid_positional_boolean_parameters, always_specify_types, experimental_member_use

extension GetEndpointTrustCollection on Isar {
  IsarCollection<EndpointTrust> get endpointTrusts => this.collection();
}

const EndpointTrustSchema = CollectionSchema(
  name: r'EndpointTrust',
  id: 7962811943592738028,
  properties: {
    r'acceptedAt': PropertySchema(
      id: 0,
      name: r'acceptedAt',
      type: IsarType.long,
    ),
    r'acceptedFingerprint': PropertySchema(
      id: 1,
      name: r'acceptedFingerprint',
      type: IsarType.string,
    ),
    r'acceptedKeyBytes': PropertySchema(
      id: 2,
      name: r'acceptedKeyBytes',
      type: IsarType.byteList,
    ),
    r'acceptedType': PropertySchema(
      id: 3,
      name: r'acceptedType',
      type: IsarType.string,
    ),
    r'changed': PropertySchema(id: 4, name: r'changed', type: IsarType.bool),
    r'detectedAt': PropertySchema(
      id: 5,
      name: r'detectedAt',
      type: IsarType.long,
    ),
    r'endpointId': PropertySchema(
      id: 6,
      name: r'endpointId',
      type: IsarType.string,
    ),
    r'lastSeenAt': PropertySchema(
      id: 7,
      name: r'lastSeenAt',
      type: IsarType.long,
    ),
    r'normalizedHost': PropertySchema(
      id: 8,
      name: r'normalizedHost',
      type: IsarType.string,
    ),
    r'observationRevision': PropertySchema(
      id: 9,
      name: r'observationRevision',
      type: IsarType.long,
    ),
    r'observedFingerprint': PropertySchema(
      id: 10,
      name: r'observedFingerprint',
      type: IsarType.string,
    ),
    r'observedKeyBytes': PropertySchema(
      id: 11,
      name: r'observedKeyBytes',
      type: IsarType.byteList,
    ),
    r'observedType': PropertySchema(
      id: 12,
      name: r'observedType',
      type: IsarType.string,
    ),
    r'port': PropertySchema(id: 13, name: r'port', type: IsarType.long),
    r'profileRefCount': PropertySchema(
      id: 14,
      name: r'profileRefCount',
      type: IsarType.long,
    ),
    r'trustRevision': PropertySchema(
      id: 15,
      name: r'trustRevision',
      type: IsarType.long,
    ),
  },

  estimateSize: _endpointTrustEstimateSize,
  serialize: _endpointTrustSerialize,
  deserialize: _endpointTrustDeserialize,
  deserializeProp: _endpointTrustDeserializeProp,
  idName: r'id',
  indexes: {
    r'endpointId': IndexSchema(
      id: -2131995512278992622,
      name: r'endpointId',
      unique: true,
      replace: false,
      properties: [
        IndexPropertySchema(
          name: r'endpointId',
          type: IndexType.hash,
          caseSensitive: true,
        ),
      ],
    ),
    r'normalizedHost_port': IndexSchema(
      id: 5518626834945125780,
      name: r'normalizedHost_port',
      unique: true,
      replace: false,
      properties: [
        IndexPropertySchema(
          name: r'normalizedHost',
          type: IndexType.hash,
          caseSensitive: true,
        ),
        IndexPropertySchema(
          name: r'port',
          type: IndexType.value,
          caseSensitive: false,
        ),
      ],
    ),
  },
  links: {},
  embeddedSchemas: {},

  getId: _endpointTrustGetId,
  getLinks: _endpointTrustGetLinks,
  attach: _endpointTrustAttach,
  version: '3.4.1',
);

int _endpointTrustEstimateSize(
  EndpointTrust object,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  var bytesCount = offsets.last;
  {
    final value = object.acceptedFingerprint;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  {
    final value = object.acceptedKeyBytes;
    if (value != null) {
      bytesCount += 3 + value.length;
    }
  }
  {
    final value = object.acceptedType;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  bytesCount += 3 + object.endpointId.length * 3;
  bytesCount += 3 + object.normalizedHost.length * 3;
  {
    final value = object.observedFingerprint;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  {
    final value = object.observedKeyBytes;
    if (value != null) {
      bytesCount += 3 + value.length;
    }
  }
  {
    final value = object.observedType;
    if (value != null) {
      bytesCount += 3 + value.length * 3;
    }
  }
  return bytesCount;
}

void _endpointTrustSerialize(
  EndpointTrust object,
  IsarWriter writer,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  writer.writeLong(offsets[0], object.acceptedAt);
  writer.writeString(offsets[1], object.acceptedFingerprint);
  writer.writeByteList(offsets[2], object.acceptedKeyBytes);
  writer.writeString(offsets[3], object.acceptedType);
  writer.writeBool(offsets[4], object.changed);
  writer.writeLong(offsets[5], object.detectedAt);
  writer.writeString(offsets[6], object.endpointId);
  writer.writeLong(offsets[7], object.lastSeenAt);
  writer.writeString(offsets[8], object.normalizedHost);
  writer.writeLong(offsets[9], object.observationRevision);
  writer.writeString(offsets[10], object.observedFingerprint);
  writer.writeByteList(offsets[11], object.observedKeyBytes);
  writer.writeString(offsets[12], object.observedType);
  writer.writeLong(offsets[13], object.port);
  writer.writeLong(offsets[14], object.profileRefCount);
  writer.writeLong(offsets[15], object.trustRevision);
}

EndpointTrust _endpointTrustDeserialize(
  Id id,
  IsarReader reader,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  final object = EndpointTrust();
  object.acceptedAt = reader.readLongOrNull(offsets[0]);
  object.acceptedFingerprint = reader.readStringOrNull(offsets[1]);
  object.acceptedKeyBytes = reader.readByteList(offsets[2]);
  object.acceptedType = reader.readStringOrNull(offsets[3]);
  object.changed = reader.readBool(offsets[4]);
  object.detectedAt = reader.readLongOrNull(offsets[5]);
  object.endpointId = reader.readString(offsets[6]);
  object.id = id;
  object.lastSeenAt = reader.readLongOrNull(offsets[7]);
  object.normalizedHost = reader.readString(offsets[8]);
  object.observationRevision = reader.readLong(offsets[9]);
  object.observedFingerprint = reader.readStringOrNull(offsets[10]);
  object.observedKeyBytes = reader.readByteList(offsets[11]);
  object.observedType = reader.readStringOrNull(offsets[12]);
  object.port = reader.readLong(offsets[13]);
  object.profileRefCount = reader.readLong(offsets[14]);
  object.trustRevision = reader.readLong(offsets[15]);
  return object;
}

P _endpointTrustDeserializeProp<P>(
  IsarReader reader,
  int propertyId,
  int offset,
  Map<Type, List<int>> allOffsets,
) {
  switch (propertyId) {
    case 0:
      return (reader.readLongOrNull(offset)) as P;
    case 1:
      return (reader.readStringOrNull(offset)) as P;
    case 2:
      return (reader.readByteList(offset)) as P;
    case 3:
      return (reader.readStringOrNull(offset)) as P;
    case 4:
      return (reader.readBool(offset)) as P;
    case 5:
      return (reader.readLongOrNull(offset)) as P;
    case 6:
      return (reader.readString(offset)) as P;
    case 7:
      return (reader.readLongOrNull(offset)) as P;
    case 8:
      return (reader.readString(offset)) as P;
    case 9:
      return (reader.readLong(offset)) as P;
    case 10:
      return (reader.readStringOrNull(offset)) as P;
    case 11:
      return (reader.readByteList(offset)) as P;
    case 12:
      return (reader.readStringOrNull(offset)) as P;
    case 13:
      return (reader.readLong(offset)) as P;
    case 14:
      return (reader.readLong(offset)) as P;
    case 15:
      return (reader.readLong(offset)) as P;
    default:
      throw IsarError('Unknown property with id $propertyId');
  }
}

Id _endpointTrustGetId(EndpointTrust object) {
  return object.id;
}

List<IsarLinkBase<dynamic>> _endpointTrustGetLinks(EndpointTrust object) {
  return [];
}

void _endpointTrustAttach(
  IsarCollection<dynamic> col,
  Id id,
  EndpointTrust object,
) {
  object.id = id;
}

extension EndpointTrustByIndex on IsarCollection<EndpointTrust> {
  Future<EndpointTrust?> getByEndpointId(String endpointId) {
    return getByIndex(r'endpointId', [endpointId]);
  }

  EndpointTrust? getByEndpointIdSync(String endpointId) {
    return getByIndexSync(r'endpointId', [endpointId]);
  }

  Future<bool> deleteByEndpointId(String endpointId) {
    return deleteByIndex(r'endpointId', [endpointId]);
  }

  bool deleteByEndpointIdSync(String endpointId) {
    return deleteByIndexSync(r'endpointId', [endpointId]);
  }

  Future<List<EndpointTrust?>> getAllByEndpointId(
    List<String> endpointIdValues,
  ) {
    final values = endpointIdValues.map((e) => [e]).toList();
    return getAllByIndex(r'endpointId', values);
  }

  List<EndpointTrust?> getAllByEndpointIdSync(List<String> endpointIdValues) {
    final values = endpointIdValues.map((e) => [e]).toList();
    return getAllByIndexSync(r'endpointId', values);
  }

  Future<int> deleteAllByEndpointId(List<String> endpointIdValues) {
    final values = endpointIdValues.map((e) => [e]).toList();
    return deleteAllByIndex(r'endpointId', values);
  }

  int deleteAllByEndpointIdSync(List<String> endpointIdValues) {
    final values = endpointIdValues.map((e) => [e]).toList();
    return deleteAllByIndexSync(r'endpointId', values);
  }

  Future<Id> putByEndpointId(EndpointTrust object) {
    return putByIndex(r'endpointId', object);
  }

  Id putByEndpointIdSync(EndpointTrust object, {bool saveLinks = true}) {
    return putByIndexSync(r'endpointId', object, saveLinks: saveLinks);
  }

  Future<List<Id>> putAllByEndpointId(List<EndpointTrust> objects) {
    return putAllByIndex(r'endpointId', objects);
  }

  List<Id> putAllByEndpointIdSync(
    List<EndpointTrust> objects, {
    bool saveLinks = true,
  }) {
    return putAllByIndexSync(r'endpointId', objects, saveLinks: saveLinks);
  }

  Future<EndpointTrust?> getByNormalizedHostPort(
    String normalizedHost,
    int port,
  ) {
    return getByIndex(r'normalizedHost_port', [normalizedHost, port]);
  }

  EndpointTrust? getByNormalizedHostPortSync(String normalizedHost, int port) {
    return getByIndexSync(r'normalizedHost_port', [normalizedHost, port]);
  }

  Future<bool> deleteByNormalizedHostPort(String normalizedHost, int port) {
    return deleteByIndex(r'normalizedHost_port', [normalizedHost, port]);
  }

  bool deleteByNormalizedHostPortSync(String normalizedHost, int port) {
    return deleteByIndexSync(r'normalizedHost_port', [normalizedHost, port]);
  }

  Future<List<EndpointTrust?>> getAllByNormalizedHostPort(
    List<String> normalizedHostValues,
    List<int> portValues,
  ) {
    final len = normalizedHostValues.length;
    assert(
      portValues.length == len,
      'All index values must have the same length',
    );
    final values = <List<dynamic>>[];
    for (var i = 0; i < len; i++) {
      values.add([normalizedHostValues[i], portValues[i]]);
    }

    return getAllByIndex(r'normalizedHost_port', values);
  }

  List<EndpointTrust?> getAllByNormalizedHostPortSync(
    List<String> normalizedHostValues,
    List<int> portValues,
  ) {
    final len = normalizedHostValues.length;
    assert(
      portValues.length == len,
      'All index values must have the same length',
    );
    final values = <List<dynamic>>[];
    for (var i = 0; i < len; i++) {
      values.add([normalizedHostValues[i], portValues[i]]);
    }

    return getAllByIndexSync(r'normalizedHost_port', values);
  }

  Future<int> deleteAllByNormalizedHostPort(
    List<String> normalizedHostValues,
    List<int> portValues,
  ) {
    final len = normalizedHostValues.length;
    assert(
      portValues.length == len,
      'All index values must have the same length',
    );
    final values = <List<dynamic>>[];
    for (var i = 0; i < len; i++) {
      values.add([normalizedHostValues[i], portValues[i]]);
    }

    return deleteAllByIndex(r'normalizedHost_port', values);
  }

  int deleteAllByNormalizedHostPortSync(
    List<String> normalizedHostValues,
    List<int> portValues,
  ) {
    final len = normalizedHostValues.length;
    assert(
      portValues.length == len,
      'All index values must have the same length',
    );
    final values = <List<dynamic>>[];
    for (var i = 0; i < len; i++) {
      values.add([normalizedHostValues[i], portValues[i]]);
    }

    return deleteAllByIndexSync(r'normalizedHost_port', values);
  }

  Future<Id> putByNormalizedHostPort(EndpointTrust object) {
    return putByIndex(r'normalizedHost_port', object);
  }

  Id putByNormalizedHostPortSync(
    EndpointTrust object, {
    bool saveLinks = true,
  }) {
    return putByIndexSync(r'normalizedHost_port', object, saveLinks: saveLinks);
  }

  Future<List<Id>> putAllByNormalizedHostPort(List<EndpointTrust> objects) {
    return putAllByIndex(r'normalizedHost_port', objects);
  }

  List<Id> putAllByNormalizedHostPortSync(
    List<EndpointTrust> objects, {
    bool saveLinks = true,
  }) {
    return putAllByIndexSync(
      r'normalizedHost_port',
      objects,
      saveLinks: saveLinks,
    );
  }
}

extension EndpointTrustQueryWhereSort
    on QueryBuilder<EndpointTrust, EndpointTrust, QWhere> {
  QueryBuilder<EndpointTrust, EndpointTrust, QAfterWhere> anyId() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(const IdWhereClause.any());
    });
  }
}

extension EndpointTrustQueryWhere
    on QueryBuilder<EndpointTrust, EndpointTrust, QWhereClause> {
  QueryBuilder<EndpointTrust, EndpointTrust, QAfterWhereClause> idEqualTo(
    Id id,
  ) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IdWhereClause.between(lower: id, upper: id));
    });
  }

  QueryBuilder<EndpointTrust, EndpointTrust, QAfterWhereClause> idNotEqualTo(
    Id id,
  ) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(
              IdWhereClause.lessThan(upper: id, includeUpper: false),
            )
            .addWhereClause(
              IdWhereClause.greaterThan(lower: id, includeLower: false),
            );
      } else {
        return query
            .addWhereClause(
              IdWhereClause.greaterThan(lower: id, includeLower: false),
            )
            .addWhereClause(
              IdWhereClause.lessThan(upper: id, includeUpper: false),
            );
      }
    });
  }

  QueryBuilder<EndpointTrust, EndpointTrust, QAfterWhereClause> idGreaterThan(
    Id id, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.greaterThan(lower: id, includeLower: include),
      );
    });
  }

  QueryBuilder<EndpointTrust, EndpointTrust, QAfterWhereClause> idLessThan(
    Id id, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.lessThan(upper: id, includeUpper: include),
      );
    });
  }

  QueryBuilder<EndpointTrust, EndpointTrust, QAfterWhereClause> idBetween(
    Id lowerId,
    Id upperId, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.between(
          lower: lowerId,
          includeLower: includeLower,
          upper: upperId,
          includeUpper: includeUpper,
        ),
      );
    });
  }

  QueryBuilder<EndpointTrust, EndpointTrust, QAfterWhereClause>
  endpointIdEqualTo(String endpointId) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IndexWhereClause.equalTo(indexName: r'endpointId', value: [endpointId]),
      );
    });
  }

  QueryBuilder<EndpointTrust, EndpointTrust, QAfterWhereClause>
  endpointIdNotEqualTo(String endpointId) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'endpointId',
                lower: [],
                upper: [endpointId],
                includeUpper: false,
              ),
            )
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'endpointId',
                lower: [endpointId],
                includeLower: false,
                upper: [],
              ),
            );
      } else {
        return query
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'endpointId',
                lower: [endpointId],
                includeLower: false,
                upper: [],
              ),
            )
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'endpointId',
                lower: [],
                upper: [endpointId],
                includeUpper: false,
              ),
            );
      }
    });
  }

  QueryBuilder<EndpointTrust, EndpointTrust, QAfterWhereClause>
  normalizedHostEqualToAnyPort(String normalizedHost) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IndexWhereClause.equalTo(
          indexName: r'normalizedHost_port',
          value: [normalizedHost],
        ),
      );
    });
  }

  QueryBuilder<EndpointTrust, EndpointTrust, QAfterWhereClause>
  normalizedHostNotEqualToAnyPort(String normalizedHost) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'normalizedHost_port',
                lower: [],
                upper: [normalizedHost],
                includeUpper: false,
              ),
            )
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'normalizedHost_port',
                lower: [normalizedHost],
                includeLower: false,
                upper: [],
              ),
            );
      } else {
        return query
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'normalizedHost_port',
                lower: [normalizedHost],
                includeLower: false,
                upper: [],
              ),
            )
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'normalizedHost_port',
                lower: [],
                upper: [normalizedHost],
                includeUpper: false,
              ),
            );
      }
    });
  }

  QueryBuilder<EndpointTrust, EndpointTrust, QAfterWhereClause>
  normalizedHostPortEqualTo(String normalizedHost, int port) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IndexWhereClause.equalTo(
          indexName: r'normalizedHost_port',
          value: [normalizedHost, port],
        ),
      );
    });
  }

  QueryBuilder<EndpointTrust, EndpointTrust, QAfterWhereClause>
  normalizedHostEqualToPortNotEqualTo(String normalizedHost, int port) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'normalizedHost_port',
                lower: [normalizedHost],
                upper: [normalizedHost, port],
                includeUpper: false,
              ),
            )
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'normalizedHost_port',
                lower: [normalizedHost, port],
                includeLower: false,
                upper: [normalizedHost],
              ),
            );
      } else {
        return query
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'normalizedHost_port',
                lower: [normalizedHost, port],
                includeLower: false,
                upper: [normalizedHost],
              ),
            )
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'normalizedHost_port',
                lower: [normalizedHost],
                upper: [normalizedHost, port],
                includeUpper: false,
              ),
            );
      }
    });
  }

  QueryBuilder<EndpointTrust, EndpointTrust, QAfterWhereClause>
  normalizedHostEqualToPortGreaterThan(
    String normalizedHost,
    int port, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IndexWhereClause.between(
          indexName: r'normalizedHost_port',
          lower: [normalizedHost, port],
          includeLower: include,
          upper: [normalizedHost],
        ),
      );
    });
  }

  QueryBuilder<EndpointTrust, EndpointTrust, QAfterWhereClause>
  normalizedHostEqualToPortLessThan(
    String normalizedHost,
    int port, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IndexWhereClause.between(
          indexName: r'normalizedHost_port',
          lower: [normalizedHost],
          upper: [normalizedHost, port],
          includeUpper: include,
        ),
      );
    });
  }

  QueryBuilder<EndpointTrust, EndpointTrust, QAfterWhereClause>
  normalizedHostEqualToPortBetween(
    String normalizedHost,
    int lowerPort,
    int upperPort, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IndexWhereClause.between(
          indexName: r'normalizedHost_port',
          lower: [normalizedHost, lowerPort],
          includeLower: includeLower,
          upper: [normalizedHost, upperPort],
          includeUpper: includeUpper,
        ),
      );
    });
  }
}

extension EndpointTrustQueryFilter
    on QueryBuilder<EndpointTrust, EndpointTrust, QFilterCondition> {
  QueryBuilder<EndpointTrust, EndpointTrust, QAfterFilterCondition>
  acceptedAtIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNull(property: r'acceptedAt'),
      );
    });
  }

  QueryBuilder<EndpointTrust, EndpointTrust, QAfterFilterCondition>
  acceptedAtIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNotNull(property: r'acceptedAt'),
      );
    });
  }

  QueryBuilder<EndpointTrust, EndpointTrust, QAfterFilterCondition>
  acceptedAtEqualTo(int? value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'acceptedAt', value: value),
      );
    });
  }

  QueryBuilder<EndpointTrust, EndpointTrust, QAfterFilterCondition>
  acceptedAtGreaterThan(int? value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'acceptedAt',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<EndpointTrust, EndpointTrust, QAfterFilterCondition>
  acceptedAtLessThan(int? value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'acceptedAt',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<EndpointTrust, EndpointTrust, QAfterFilterCondition>
  acceptedAtBetween(
    int? lower,
    int? upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'acceptedAt',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
        ),
      );
    });
  }

  QueryBuilder<EndpointTrust, EndpointTrust, QAfterFilterCondition>
  acceptedFingerprintIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNull(property: r'acceptedFingerprint'),
      );
    });
  }

  QueryBuilder<EndpointTrust, EndpointTrust, QAfterFilterCondition>
  acceptedFingerprintIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNotNull(property: r'acceptedFingerprint'),
      );
    });
  }

  QueryBuilder<EndpointTrust, EndpointTrust, QAfterFilterCondition>
  acceptedFingerprintEqualTo(String? value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'acceptedFingerprint',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<EndpointTrust, EndpointTrust, QAfterFilterCondition>
  acceptedFingerprintGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'acceptedFingerprint',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<EndpointTrust, EndpointTrust, QAfterFilterCondition>
  acceptedFingerprintLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'acceptedFingerprint',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<EndpointTrust, EndpointTrust, QAfterFilterCondition>
  acceptedFingerprintBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'acceptedFingerprint',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<EndpointTrust, EndpointTrust, QAfterFilterCondition>
  acceptedFingerprintStartsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.startsWith(
          property: r'acceptedFingerprint',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<EndpointTrust, EndpointTrust, QAfterFilterCondition>
  acceptedFingerprintEndsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.endsWith(
          property: r'acceptedFingerprint',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<EndpointTrust, EndpointTrust, QAfterFilterCondition>
  acceptedFingerprintContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.contains(
          property: r'acceptedFingerprint',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<EndpointTrust, EndpointTrust, QAfterFilterCondition>
  acceptedFingerprintMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.matches(
          property: r'acceptedFingerprint',
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<EndpointTrust, EndpointTrust, QAfterFilterCondition>
  acceptedFingerprintIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'acceptedFingerprint', value: ''),
      );
    });
  }

  QueryBuilder<EndpointTrust, EndpointTrust, QAfterFilterCondition>
  acceptedFingerprintIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          property: r'acceptedFingerprint',
          value: '',
        ),
      );
    });
  }

  QueryBuilder<EndpointTrust, EndpointTrust, QAfterFilterCondition>
  acceptedKeyBytesIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNull(property: r'acceptedKeyBytes'),
      );
    });
  }

  QueryBuilder<EndpointTrust, EndpointTrust, QAfterFilterCondition>
  acceptedKeyBytesIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNotNull(property: r'acceptedKeyBytes'),
      );
    });
  }

  QueryBuilder<EndpointTrust, EndpointTrust, QAfterFilterCondition>
  acceptedKeyBytesElementEqualTo(int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'acceptedKeyBytes', value: value),
      );
    });
  }

  QueryBuilder<EndpointTrust, EndpointTrust, QAfterFilterCondition>
  acceptedKeyBytesElementGreaterThan(int value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'acceptedKeyBytes',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<EndpointTrust, EndpointTrust, QAfterFilterCondition>
  acceptedKeyBytesElementLessThan(int value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'acceptedKeyBytes',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<EndpointTrust, EndpointTrust, QAfterFilterCondition>
  acceptedKeyBytesElementBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'acceptedKeyBytes',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
        ),
      );
    });
  }

  QueryBuilder<EndpointTrust, EndpointTrust, QAfterFilterCondition>
  acceptedKeyBytesLengthEqualTo(int length) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(r'acceptedKeyBytes', length, true, length, true);
    });
  }

  QueryBuilder<EndpointTrust, EndpointTrust, QAfterFilterCondition>
  acceptedKeyBytesIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(r'acceptedKeyBytes', 0, true, 0, true);
    });
  }

  QueryBuilder<EndpointTrust, EndpointTrust, QAfterFilterCondition>
  acceptedKeyBytesIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(r'acceptedKeyBytes', 0, false, 999999, true);
    });
  }

  QueryBuilder<EndpointTrust, EndpointTrust, QAfterFilterCondition>
  acceptedKeyBytesLengthLessThan(int length, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(r'acceptedKeyBytes', 0, true, length, include);
    });
  }

  QueryBuilder<EndpointTrust, EndpointTrust, QAfterFilterCondition>
  acceptedKeyBytesLengthGreaterThan(int length, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'acceptedKeyBytes',
        length,
        include,
        999999,
        true,
      );
    });
  }

  QueryBuilder<EndpointTrust, EndpointTrust, QAfterFilterCondition>
  acceptedKeyBytesLengthBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'acceptedKeyBytes',
        lower,
        includeLower,
        upper,
        includeUpper,
      );
    });
  }

  QueryBuilder<EndpointTrust, EndpointTrust, QAfterFilterCondition>
  acceptedTypeIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNull(property: r'acceptedType'),
      );
    });
  }

  QueryBuilder<EndpointTrust, EndpointTrust, QAfterFilterCondition>
  acceptedTypeIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNotNull(property: r'acceptedType'),
      );
    });
  }

  QueryBuilder<EndpointTrust, EndpointTrust, QAfterFilterCondition>
  acceptedTypeEqualTo(String? value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'acceptedType',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<EndpointTrust, EndpointTrust, QAfterFilterCondition>
  acceptedTypeGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'acceptedType',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<EndpointTrust, EndpointTrust, QAfterFilterCondition>
  acceptedTypeLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'acceptedType',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<EndpointTrust, EndpointTrust, QAfterFilterCondition>
  acceptedTypeBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'acceptedType',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<EndpointTrust, EndpointTrust, QAfterFilterCondition>
  acceptedTypeStartsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.startsWith(
          property: r'acceptedType',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<EndpointTrust, EndpointTrust, QAfterFilterCondition>
  acceptedTypeEndsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.endsWith(
          property: r'acceptedType',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<EndpointTrust, EndpointTrust, QAfterFilterCondition>
  acceptedTypeContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.contains(
          property: r'acceptedType',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<EndpointTrust, EndpointTrust, QAfterFilterCondition>
  acceptedTypeMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.matches(
          property: r'acceptedType',
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<EndpointTrust, EndpointTrust, QAfterFilterCondition>
  acceptedTypeIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'acceptedType', value: ''),
      );
    });
  }

  QueryBuilder<EndpointTrust, EndpointTrust, QAfterFilterCondition>
  acceptedTypeIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(property: r'acceptedType', value: ''),
      );
    });
  }

  QueryBuilder<EndpointTrust, EndpointTrust, QAfterFilterCondition>
  changedEqualTo(bool value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'changed', value: value),
      );
    });
  }

  QueryBuilder<EndpointTrust, EndpointTrust, QAfterFilterCondition>
  detectedAtIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNull(property: r'detectedAt'),
      );
    });
  }

  QueryBuilder<EndpointTrust, EndpointTrust, QAfterFilterCondition>
  detectedAtIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNotNull(property: r'detectedAt'),
      );
    });
  }

  QueryBuilder<EndpointTrust, EndpointTrust, QAfterFilterCondition>
  detectedAtEqualTo(int? value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'detectedAt', value: value),
      );
    });
  }

  QueryBuilder<EndpointTrust, EndpointTrust, QAfterFilterCondition>
  detectedAtGreaterThan(int? value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'detectedAt',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<EndpointTrust, EndpointTrust, QAfterFilterCondition>
  detectedAtLessThan(int? value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'detectedAt',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<EndpointTrust, EndpointTrust, QAfterFilterCondition>
  detectedAtBetween(
    int? lower,
    int? upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'detectedAt',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
        ),
      );
    });
  }

  QueryBuilder<EndpointTrust, EndpointTrust, QAfterFilterCondition>
  endpointIdEqualTo(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'endpointId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<EndpointTrust, EndpointTrust, QAfterFilterCondition>
  endpointIdGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'endpointId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<EndpointTrust, EndpointTrust, QAfterFilterCondition>
  endpointIdLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'endpointId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<EndpointTrust, EndpointTrust, QAfterFilterCondition>
  endpointIdBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'endpointId',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<EndpointTrust, EndpointTrust, QAfterFilterCondition>
  endpointIdStartsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.startsWith(
          property: r'endpointId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<EndpointTrust, EndpointTrust, QAfterFilterCondition>
  endpointIdEndsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.endsWith(
          property: r'endpointId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<EndpointTrust, EndpointTrust, QAfterFilterCondition>
  endpointIdContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.contains(
          property: r'endpointId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<EndpointTrust, EndpointTrust, QAfterFilterCondition>
  endpointIdMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.matches(
          property: r'endpointId',
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<EndpointTrust, EndpointTrust, QAfterFilterCondition>
  endpointIdIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'endpointId', value: ''),
      );
    });
  }

  QueryBuilder<EndpointTrust, EndpointTrust, QAfterFilterCondition>
  endpointIdIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(property: r'endpointId', value: ''),
      );
    });
  }

  QueryBuilder<EndpointTrust, EndpointTrust, QAfterFilterCondition> idEqualTo(
    Id value,
  ) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'id', value: value),
      );
    });
  }

  QueryBuilder<EndpointTrust, EndpointTrust, QAfterFilterCondition>
  idGreaterThan(Id value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'id',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<EndpointTrust, EndpointTrust, QAfterFilterCondition> idLessThan(
    Id value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'id',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<EndpointTrust, EndpointTrust, QAfterFilterCondition> idBetween(
    Id lower,
    Id upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'id',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
        ),
      );
    });
  }

  QueryBuilder<EndpointTrust, EndpointTrust, QAfterFilterCondition>
  lastSeenAtIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNull(property: r'lastSeenAt'),
      );
    });
  }

  QueryBuilder<EndpointTrust, EndpointTrust, QAfterFilterCondition>
  lastSeenAtIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNotNull(property: r'lastSeenAt'),
      );
    });
  }

  QueryBuilder<EndpointTrust, EndpointTrust, QAfterFilterCondition>
  lastSeenAtEqualTo(int? value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'lastSeenAt', value: value),
      );
    });
  }

  QueryBuilder<EndpointTrust, EndpointTrust, QAfterFilterCondition>
  lastSeenAtGreaterThan(int? value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'lastSeenAt',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<EndpointTrust, EndpointTrust, QAfterFilterCondition>
  lastSeenAtLessThan(int? value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'lastSeenAt',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<EndpointTrust, EndpointTrust, QAfterFilterCondition>
  lastSeenAtBetween(
    int? lower,
    int? upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'lastSeenAt',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
        ),
      );
    });
  }

  QueryBuilder<EndpointTrust, EndpointTrust, QAfterFilterCondition>
  normalizedHostEqualTo(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'normalizedHost',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<EndpointTrust, EndpointTrust, QAfterFilterCondition>
  normalizedHostGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'normalizedHost',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<EndpointTrust, EndpointTrust, QAfterFilterCondition>
  normalizedHostLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'normalizedHost',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<EndpointTrust, EndpointTrust, QAfterFilterCondition>
  normalizedHostBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'normalizedHost',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<EndpointTrust, EndpointTrust, QAfterFilterCondition>
  normalizedHostStartsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.startsWith(
          property: r'normalizedHost',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<EndpointTrust, EndpointTrust, QAfterFilterCondition>
  normalizedHostEndsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.endsWith(
          property: r'normalizedHost',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<EndpointTrust, EndpointTrust, QAfterFilterCondition>
  normalizedHostContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.contains(
          property: r'normalizedHost',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<EndpointTrust, EndpointTrust, QAfterFilterCondition>
  normalizedHostMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.matches(
          property: r'normalizedHost',
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<EndpointTrust, EndpointTrust, QAfterFilterCondition>
  normalizedHostIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'normalizedHost', value: ''),
      );
    });
  }

  QueryBuilder<EndpointTrust, EndpointTrust, QAfterFilterCondition>
  normalizedHostIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(property: r'normalizedHost', value: ''),
      );
    });
  }

  QueryBuilder<EndpointTrust, EndpointTrust, QAfterFilterCondition>
  observationRevisionEqualTo(int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'observationRevision', value: value),
      );
    });
  }

  QueryBuilder<EndpointTrust, EndpointTrust, QAfterFilterCondition>
  observationRevisionGreaterThan(int value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'observationRevision',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<EndpointTrust, EndpointTrust, QAfterFilterCondition>
  observationRevisionLessThan(int value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'observationRevision',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<EndpointTrust, EndpointTrust, QAfterFilterCondition>
  observationRevisionBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'observationRevision',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
        ),
      );
    });
  }

  QueryBuilder<EndpointTrust, EndpointTrust, QAfterFilterCondition>
  observedFingerprintIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNull(property: r'observedFingerprint'),
      );
    });
  }

  QueryBuilder<EndpointTrust, EndpointTrust, QAfterFilterCondition>
  observedFingerprintIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNotNull(property: r'observedFingerprint'),
      );
    });
  }

  QueryBuilder<EndpointTrust, EndpointTrust, QAfterFilterCondition>
  observedFingerprintEqualTo(String? value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'observedFingerprint',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<EndpointTrust, EndpointTrust, QAfterFilterCondition>
  observedFingerprintGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'observedFingerprint',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<EndpointTrust, EndpointTrust, QAfterFilterCondition>
  observedFingerprintLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'observedFingerprint',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<EndpointTrust, EndpointTrust, QAfterFilterCondition>
  observedFingerprintBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'observedFingerprint',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<EndpointTrust, EndpointTrust, QAfterFilterCondition>
  observedFingerprintStartsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.startsWith(
          property: r'observedFingerprint',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<EndpointTrust, EndpointTrust, QAfterFilterCondition>
  observedFingerprintEndsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.endsWith(
          property: r'observedFingerprint',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<EndpointTrust, EndpointTrust, QAfterFilterCondition>
  observedFingerprintContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.contains(
          property: r'observedFingerprint',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<EndpointTrust, EndpointTrust, QAfterFilterCondition>
  observedFingerprintMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.matches(
          property: r'observedFingerprint',
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<EndpointTrust, EndpointTrust, QAfterFilterCondition>
  observedFingerprintIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'observedFingerprint', value: ''),
      );
    });
  }

  QueryBuilder<EndpointTrust, EndpointTrust, QAfterFilterCondition>
  observedFingerprintIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          property: r'observedFingerprint',
          value: '',
        ),
      );
    });
  }

  QueryBuilder<EndpointTrust, EndpointTrust, QAfterFilterCondition>
  observedKeyBytesIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNull(property: r'observedKeyBytes'),
      );
    });
  }

  QueryBuilder<EndpointTrust, EndpointTrust, QAfterFilterCondition>
  observedKeyBytesIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNotNull(property: r'observedKeyBytes'),
      );
    });
  }

  QueryBuilder<EndpointTrust, EndpointTrust, QAfterFilterCondition>
  observedKeyBytesElementEqualTo(int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'observedKeyBytes', value: value),
      );
    });
  }

  QueryBuilder<EndpointTrust, EndpointTrust, QAfterFilterCondition>
  observedKeyBytesElementGreaterThan(int value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'observedKeyBytes',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<EndpointTrust, EndpointTrust, QAfterFilterCondition>
  observedKeyBytesElementLessThan(int value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'observedKeyBytes',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<EndpointTrust, EndpointTrust, QAfterFilterCondition>
  observedKeyBytesElementBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'observedKeyBytes',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
        ),
      );
    });
  }

  QueryBuilder<EndpointTrust, EndpointTrust, QAfterFilterCondition>
  observedKeyBytesLengthEqualTo(int length) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(r'observedKeyBytes', length, true, length, true);
    });
  }

  QueryBuilder<EndpointTrust, EndpointTrust, QAfterFilterCondition>
  observedKeyBytesIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(r'observedKeyBytes', 0, true, 0, true);
    });
  }

  QueryBuilder<EndpointTrust, EndpointTrust, QAfterFilterCondition>
  observedKeyBytesIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(r'observedKeyBytes', 0, false, 999999, true);
    });
  }

  QueryBuilder<EndpointTrust, EndpointTrust, QAfterFilterCondition>
  observedKeyBytesLengthLessThan(int length, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(r'observedKeyBytes', 0, true, length, include);
    });
  }

  QueryBuilder<EndpointTrust, EndpointTrust, QAfterFilterCondition>
  observedKeyBytesLengthGreaterThan(int length, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'observedKeyBytes',
        length,
        include,
        999999,
        true,
      );
    });
  }

  QueryBuilder<EndpointTrust, EndpointTrust, QAfterFilterCondition>
  observedKeyBytesLengthBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'observedKeyBytes',
        lower,
        includeLower,
        upper,
        includeUpper,
      );
    });
  }

  QueryBuilder<EndpointTrust, EndpointTrust, QAfterFilterCondition>
  observedTypeIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNull(property: r'observedType'),
      );
    });
  }

  QueryBuilder<EndpointTrust, EndpointTrust, QAfterFilterCondition>
  observedTypeIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNotNull(property: r'observedType'),
      );
    });
  }

  QueryBuilder<EndpointTrust, EndpointTrust, QAfterFilterCondition>
  observedTypeEqualTo(String? value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'observedType',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<EndpointTrust, EndpointTrust, QAfterFilterCondition>
  observedTypeGreaterThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'observedType',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<EndpointTrust, EndpointTrust, QAfterFilterCondition>
  observedTypeLessThan(
    String? value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'observedType',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<EndpointTrust, EndpointTrust, QAfterFilterCondition>
  observedTypeBetween(
    String? lower,
    String? upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'observedType',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<EndpointTrust, EndpointTrust, QAfterFilterCondition>
  observedTypeStartsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.startsWith(
          property: r'observedType',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<EndpointTrust, EndpointTrust, QAfterFilterCondition>
  observedTypeEndsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.endsWith(
          property: r'observedType',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<EndpointTrust, EndpointTrust, QAfterFilterCondition>
  observedTypeContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.contains(
          property: r'observedType',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<EndpointTrust, EndpointTrust, QAfterFilterCondition>
  observedTypeMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.matches(
          property: r'observedType',
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<EndpointTrust, EndpointTrust, QAfterFilterCondition>
  observedTypeIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'observedType', value: ''),
      );
    });
  }

  QueryBuilder<EndpointTrust, EndpointTrust, QAfterFilterCondition>
  observedTypeIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(property: r'observedType', value: ''),
      );
    });
  }

  QueryBuilder<EndpointTrust, EndpointTrust, QAfterFilterCondition> portEqualTo(
    int value,
  ) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'port', value: value),
      );
    });
  }

  QueryBuilder<EndpointTrust, EndpointTrust, QAfterFilterCondition>
  portGreaterThan(int value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'port',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<EndpointTrust, EndpointTrust, QAfterFilterCondition>
  portLessThan(int value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'port',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<EndpointTrust, EndpointTrust, QAfterFilterCondition> portBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'port',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
        ),
      );
    });
  }

  QueryBuilder<EndpointTrust, EndpointTrust, QAfterFilterCondition>
  profileRefCountEqualTo(int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'profileRefCount', value: value),
      );
    });
  }

  QueryBuilder<EndpointTrust, EndpointTrust, QAfterFilterCondition>
  profileRefCountGreaterThan(int value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'profileRefCount',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<EndpointTrust, EndpointTrust, QAfterFilterCondition>
  profileRefCountLessThan(int value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'profileRefCount',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<EndpointTrust, EndpointTrust, QAfterFilterCondition>
  profileRefCountBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'profileRefCount',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
        ),
      );
    });
  }

  QueryBuilder<EndpointTrust, EndpointTrust, QAfterFilterCondition>
  trustRevisionEqualTo(int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'trustRevision', value: value),
      );
    });
  }

  QueryBuilder<EndpointTrust, EndpointTrust, QAfterFilterCondition>
  trustRevisionGreaterThan(int value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'trustRevision',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<EndpointTrust, EndpointTrust, QAfterFilterCondition>
  trustRevisionLessThan(int value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'trustRevision',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<EndpointTrust, EndpointTrust, QAfterFilterCondition>
  trustRevisionBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'trustRevision',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
        ),
      );
    });
  }
}

extension EndpointTrustQueryObject
    on QueryBuilder<EndpointTrust, EndpointTrust, QFilterCondition> {}

extension EndpointTrustQueryLinks
    on QueryBuilder<EndpointTrust, EndpointTrust, QFilterCondition> {}

extension EndpointTrustQuerySortBy
    on QueryBuilder<EndpointTrust, EndpointTrust, QSortBy> {
  QueryBuilder<EndpointTrust, EndpointTrust, QAfterSortBy> sortByAcceptedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'acceptedAt', Sort.asc);
    });
  }

  QueryBuilder<EndpointTrust, EndpointTrust, QAfterSortBy>
  sortByAcceptedAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'acceptedAt', Sort.desc);
    });
  }

  QueryBuilder<EndpointTrust, EndpointTrust, QAfterSortBy>
  sortByAcceptedFingerprint() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'acceptedFingerprint', Sort.asc);
    });
  }

  QueryBuilder<EndpointTrust, EndpointTrust, QAfterSortBy>
  sortByAcceptedFingerprintDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'acceptedFingerprint', Sort.desc);
    });
  }

  QueryBuilder<EndpointTrust, EndpointTrust, QAfterSortBy>
  sortByAcceptedType() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'acceptedType', Sort.asc);
    });
  }

  QueryBuilder<EndpointTrust, EndpointTrust, QAfterSortBy>
  sortByAcceptedTypeDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'acceptedType', Sort.desc);
    });
  }

  QueryBuilder<EndpointTrust, EndpointTrust, QAfterSortBy> sortByChanged() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'changed', Sort.asc);
    });
  }

  QueryBuilder<EndpointTrust, EndpointTrust, QAfterSortBy> sortByChangedDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'changed', Sort.desc);
    });
  }

  QueryBuilder<EndpointTrust, EndpointTrust, QAfterSortBy> sortByDetectedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'detectedAt', Sort.asc);
    });
  }

  QueryBuilder<EndpointTrust, EndpointTrust, QAfterSortBy>
  sortByDetectedAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'detectedAt', Sort.desc);
    });
  }

  QueryBuilder<EndpointTrust, EndpointTrust, QAfterSortBy> sortByEndpointId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'endpointId', Sort.asc);
    });
  }

  QueryBuilder<EndpointTrust, EndpointTrust, QAfterSortBy>
  sortByEndpointIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'endpointId', Sort.desc);
    });
  }

  QueryBuilder<EndpointTrust, EndpointTrust, QAfterSortBy> sortByLastSeenAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lastSeenAt', Sort.asc);
    });
  }

  QueryBuilder<EndpointTrust, EndpointTrust, QAfterSortBy>
  sortByLastSeenAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lastSeenAt', Sort.desc);
    });
  }

  QueryBuilder<EndpointTrust, EndpointTrust, QAfterSortBy>
  sortByNormalizedHost() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'normalizedHost', Sort.asc);
    });
  }

  QueryBuilder<EndpointTrust, EndpointTrust, QAfterSortBy>
  sortByNormalizedHostDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'normalizedHost', Sort.desc);
    });
  }

  QueryBuilder<EndpointTrust, EndpointTrust, QAfterSortBy>
  sortByObservationRevision() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'observationRevision', Sort.asc);
    });
  }

  QueryBuilder<EndpointTrust, EndpointTrust, QAfterSortBy>
  sortByObservationRevisionDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'observationRevision', Sort.desc);
    });
  }

  QueryBuilder<EndpointTrust, EndpointTrust, QAfterSortBy>
  sortByObservedFingerprint() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'observedFingerprint', Sort.asc);
    });
  }

  QueryBuilder<EndpointTrust, EndpointTrust, QAfterSortBy>
  sortByObservedFingerprintDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'observedFingerprint', Sort.desc);
    });
  }

  QueryBuilder<EndpointTrust, EndpointTrust, QAfterSortBy>
  sortByObservedType() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'observedType', Sort.asc);
    });
  }

  QueryBuilder<EndpointTrust, EndpointTrust, QAfterSortBy>
  sortByObservedTypeDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'observedType', Sort.desc);
    });
  }

  QueryBuilder<EndpointTrust, EndpointTrust, QAfterSortBy> sortByPort() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'port', Sort.asc);
    });
  }

  QueryBuilder<EndpointTrust, EndpointTrust, QAfterSortBy> sortByPortDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'port', Sort.desc);
    });
  }

  QueryBuilder<EndpointTrust, EndpointTrust, QAfterSortBy>
  sortByProfileRefCount() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'profileRefCount', Sort.asc);
    });
  }

  QueryBuilder<EndpointTrust, EndpointTrust, QAfterSortBy>
  sortByProfileRefCountDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'profileRefCount', Sort.desc);
    });
  }

  QueryBuilder<EndpointTrust, EndpointTrust, QAfterSortBy>
  sortByTrustRevision() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'trustRevision', Sort.asc);
    });
  }

  QueryBuilder<EndpointTrust, EndpointTrust, QAfterSortBy>
  sortByTrustRevisionDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'trustRevision', Sort.desc);
    });
  }
}

extension EndpointTrustQuerySortThenBy
    on QueryBuilder<EndpointTrust, EndpointTrust, QSortThenBy> {
  QueryBuilder<EndpointTrust, EndpointTrust, QAfterSortBy> thenByAcceptedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'acceptedAt', Sort.asc);
    });
  }

  QueryBuilder<EndpointTrust, EndpointTrust, QAfterSortBy>
  thenByAcceptedAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'acceptedAt', Sort.desc);
    });
  }

  QueryBuilder<EndpointTrust, EndpointTrust, QAfterSortBy>
  thenByAcceptedFingerprint() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'acceptedFingerprint', Sort.asc);
    });
  }

  QueryBuilder<EndpointTrust, EndpointTrust, QAfterSortBy>
  thenByAcceptedFingerprintDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'acceptedFingerprint', Sort.desc);
    });
  }

  QueryBuilder<EndpointTrust, EndpointTrust, QAfterSortBy>
  thenByAcceptedType() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'acceptedType', Sort.asc);
    });
  }

  QueryBuilder<EndpointTrust, EndpointTrust, QAfterSortBy>
  thenByAcceptedTypeDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'acceptedType', Sort.desc);
    });
  }

  QueryBuilder<EndpointTrust, EndpointTrust, QAfterSortBy> thenByChanged() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'changed', Sort.asc);
    });
  }

  QueryBuilder<EndpointTrust, EndpointTrust, QAfterSortBy> thenByChangedDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'changed', Sort.desc);
    });
  }

  QueryBuilder<EndpointTrust, EndpointTrust, QAfterSortBy> thenByDetectedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'detectedAt', Sort.asc);
    });
  }

  QueryBuilder<EndpointTrust, EndpointTrust, QAfterSortBy>
  thenByDetectedAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'detectedAt', Sort.desc);
    });
  }

  QueryBuilder<EndpointTrust, EndpointTrust, QAfterSortBy> thenByEndpointId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'endpointId', Sort.asc);
    });
  }

  QueryBuilder<EndpointTrust, EndpointTrust, QAfterSortBy>
  thenByEndpointIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'endpointId', Sort.desc);
    });
  }

  QueryBuilder<EndpointTrust, EndpointTrust, QAfterSortBy> thenById() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.asc);
    });
  }

  QueryBuilder<EndpointTrust, EndpointTrust, QAfterSortBy> thenByIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.desc);
    });
  }

  QueryBuilder<EndpointTrust, EndpointTrust, QAfterSortBy> thenByLastSeenAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lastSeenAt', Sort.asc);
    });
  }

  QueryBuilder<EndpointTrust, EndpointTrust, QAfterSortBy>
  thenByLastSeenAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lastSeenAt', Sort.desc);
    });
  }

  QueryBuilder<EndpointTrust, EndpointTrust, QAfterSortBy>
  thenByNormalizedHost() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'normalizedHost', Sort.asc);
    });
  }

  QueryBuilder<EndpointTrust, EndpointTrust, QAfterSortBy>
  thenByNormalizedHostDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'normalizedHost', Sort.desc);
    });
  }

  QueryBuilder<EndpointTrust, EndpointTrust, QAfterSortBy>
  thenByObservationRevision() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'observationRevision', Sort.asc);
    });
  }

  QueryBuilder<EndpointTrust, EndpointTrust, QAfterSortBy>
  thenByObservationRevisionDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'observationRevision', Sort.desc);
    });
  }

  QueryBuilder<EndpointTrust, EndpointTrust, QAfterSortBy>
  thenByObservedFingerprint() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'observedFingerprint', Sort.asc);
    });
  }

  QueryBuilder<EndpointTrust, EndpointTrust, QAfterSortBy>
  thenByObservedFingerprintDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'observedFingerprint', Sort.desc);
    });
  }

  QueryBuilder<EndpointTrust, EndpointTrust, QAfterSortBy>
  thenByObservedType() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'observedType', Sort.asc);
    });
  }

  QueryBuilder<EndpointTrust, EndpointTrust, QAfterSortBy>
  thenByObservedTypeDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'observedType', Sort.desc);
    });
  }

  QueryBuilder<EndpointTrust, EndpointTrust, QAfterSortBy> thenByPort() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'port', Sort.asc);
    });
  }

  QueryBuilder<EndpointTrust, EndpointTrust, QAfterSortBy> thenByPortDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'port', Sort.desc);
    });
  }

  QueryBuilder<EndpointTrust, EndpointTrust, QAfterSortBy>
  thenByProfileRefCount() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'profileRefCount', Sort.asc);
    });
  }

  QueryBuilder<EndpointTrust, EndpointTrust, QAfterSortBy>
  thenByProfileRefCountDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'profileRefCount', Sort.desc);
    });
  }

  QueryBuilder<EndpointTrust, EndpointTrust, QAfterSortBy>
  thenByTrustRevision() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'trustRevision', Sort.asc);
    });
  }

  QueryBuilder<EndpointTrust, EndpointTrust, QAfterSortBy>
  thenByTrustRevisionDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'trustRevision', Sort.desc);
    });
  }
}

extension EndpointTrustQueryWhereDistinct
    on QueryBuilder<EndpointTrust, EndpointTrust, QDistinct> {
  QueryBuilder<EndpointTrust, EndpointTrust, QDistinct> distinctByAcceptedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'acceptedAt');
    });
  }

  QueryBuilder<EndpointTrust, EndpointTrust, QDistinct>
  distinctByAcceptedFingerprint({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(
        r'acceptedFingerprint',
        caseSensitive: caseSensitive,
      );
    });
  }

  QueryBuilder<EndpointTrust, EndpointTrust, QDistinct>
  distinctByAcceptedKeyBytes() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'acceptedKeyBytes');
    });
  }

  QueryBuilder<EndpointTrust, EndpointTrust, QDistinct> distinctByAcceptedType({
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'acceptedType', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<EndpointTrust, EndpointTrust, QDistinct> distinctByChanged() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'changed');
    });
  }

  QueryBuilder<EndpointTrust, EndpointTrust, QDistinct> distinctByDetectedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'detectedAt');
    });
  }

  QueryBuilder<EndpointTrust, EndpointTrust, QDistinct> distinctByEndpointId({
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'endpointId', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<EndpointTrust, EndpointTrust, QDistinct> distinctByLastSeenAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'lastSeenAt');
    });
  }

  QueryBuilder<EndpointTrust, EndpointTrust, QDistinct>
  distinctByNormalizedHost({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(
        r'normalizedHost',
        caseSensitive: caseSensitive,
      );
    });
  }

  QueryBuilder<EndpointTrust, EndpointTrust, QDistinct>
  distinctByObservationRevision() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'observationRevision');
    });
  }

  QueryBuilder<EndpointTrust, EndpointTrust, QDistinct>
  distinctByObservedFingerprint({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(
        r'observedFingerprint',
        caseSensitive: caseSensitive,
      );
    });
  }

  QueryBuilder<EndpointTrust, EndpointTrust, QDistinct>
  distinctByObservedKeyBytes() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'observedKeyBytes');
    });
  }

  QueryBuilder<EndpointTrust, EndpointTrust, QDistinct> distinctByObservedType({
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'observedType', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<EndpointTrust, EndpointTrust, QDistinct> distinctByPort() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'port');
    });
  }

  QueryBuilder<EndpointTrust, EndpointTrust, QDistinct>
  distinctByProfileRefCount() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'profileRefCount');
    });
  }

  QueryBuilder<EndpointTrust, EndpointTrust, QDistinct>
  distinctByTrustRevision() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'trustRevision');
    });
  }
}

extension EndpointTrustQueryProperty
    on QueryBuilder<EndpointTrust, EndpointTrust, QQueryProperty> {
  QueryBuilder<EndpointTrust, int, QQueryOperations> idProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'id');
    });
  }

  QueryBuilder<EndpointTrust, int?, QQueryOperations> acceptedAtProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'acceptedAt');
    });
  }

  QueryBuilder<EndpointTrust, String?, QQueryOperations>
  acceptedFingerprintProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'acceptedFingerprint');
    });
  }

  QueryBuilder<EndpointTrust, List<int>?, QQueryOperations>
  acceptedKeyBytesProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'acceptedKeyBytes');
    });
  }

  QueryBuilder<EndpointTrust, String?, QQueryOperations>
  acceptedTypeProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'acceptedType');
    });
  }

  QueryBuilder<EndpointTrust, bool, QQueryOperations> changedProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'changed');
    });
  }

  QueryBuilder<EndpointTrust, int?, QQueryOperations> detectedAtProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'detectedAt');
    });
  }

  QueryBuilder<EndpointTrust, String, QQueryOperations> endpointIdProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'endpointId');
    });
  }

  QueryBuilder<EndpointTrust, int?, QQueryOperations> lastSeenAtProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'lastSeenAt');
    });
  }

  QueryBuilder<EndpointTrust, String, QQueryOperations>
  normalizedHostProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'normalizedHost');
    });
  }

  QueryBuilder<EndpointTrust, int, QQueryOperations>
  observationRevisionProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'observationRevision');
    });
  }

  QueryBuilder<EndpointTrust, String?, QQueryOperations>
  observedFingerprintProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'observedFingerprint');
    });
  }

  QueryBuilder<EndpointTrust, List<int>?, QQueryOperations>
  observedKeyBytesProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'observedKeyBytes');
    });
  }

  QueryBuilder<EndpointTrust, String?, QQueryOperations>
  observedTypeProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'observedType');
    });
  }

  QueryBuilder<EndpointTrust, int, QQueryOperations> portProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'port');
    });
  }

  QueryBuilder<EndpointTrust, int, QQueryOperations> profileRefCountProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'profileRefCount');
    });
  }

  QueryBuilder<EndpointTrust, int, QQueryOperations> trustRevisionProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'trustRevision');
    });
  }
}

// coverage:ignore-file
// ignore_for_file: duplicate_ignore, non_constant_identifier_names, constant_identifier_names, invalid_use_of_protected_member, unnecessary_cast, prefer_const_constructors, lines_longer_than_80_chars, require_trailing_commas, inference_failure_on_function_invocation, unnecessary_parenthesis, unnecessary_raw_strings, unnecessary_null_checks, join_return_with_assignment, prefer_final_locals, avoid_js_rounded_ints, avoid_positional_boolean_parameters, always_specify_types, experimental_member_use

extension GetMcpGrantCollection on Isar {
  IsarCollection<McpGrant> get mcpGrants => this.collection();
}

const McpGrantSchema = CollectionSchema(
  name: r'McpGrant',
  id: 3492188278306155320,
  properties: {
    r'authorizationEpoch': PropertySchema(
      id: 0,
      name: r'authorizationEpoch',
      type: IsarType.long,
    ),
    r'clientId': PropertySchema(
      id: 1,
      name: r'clientId',
      type: IsarType.string,
    ),
    r'createdAt': PropertySchema(
      id: 2,
      name: r'createdAt',
      type: IsarType.long,
    ),
    r'expiresAt': PropertySchema(
      id: 3,
      name: r'expiresAt',
      type: IsarType.long,
    ),
    r'exportPending': PropertySchema(
      id: 4,
      name: r'exportPending',
      type: IsarType.bool,
    ),
    r'grantVersion': PropertySchema(
      id: 5,
      name: r'grantVersion',
      type: IsarType.long,
    ),
    r'name': PropertySchema(id: 6, name: r'name', type: IsarType.string),
    r'ownerUserSid': PropertySchema(
      id: 7,
      name: r'ownerUserSid',
      type: IsarType.string,
    ),
    r'protectedSecret': PropertySchema(
      id: 8,
      name: r'protectedSecret',
      type: IsarType.byteList,
    ),
    r'revokedAt': PropertySchema(
      id: 9,
      name: r'revokedAt',
      type: IsarType.long,
    ),
  },

  estimateSize: _mcpGrantEstimateSize,
  serialize: _mcpGrantSerialize,
  deserialize: _mcpGrantDeserialize,
  deserializeProp: _mcpGrantDeserializeProp,
  idName: r'id',
  indexes: {
    r'clientId': IndexSchema(
      id: 2639372232964765565,
      name: r'clientId',
      unique: true,
      replace: false,
      properties: [
        IndexPropertySchema(
          name: r'clientId',
          type: IndexType.hash,
          caseSensitive: true,
        ),
      ],
    ),
    r'expiresAt': IndexSchema(
      id: 4994901953235663716,
      name: r'expiresAt',
      unique: false,
      replace: false,
      properties: [
        IndexPropertySchema(
          name: r'expiresAt',
          type: IndexType.value,
          caseSensitive: false,
        ),
      ],
    ),
  },
  links: {},
  embeddedSchemas: {},

  getId: _mcpGrantGetId,
  getLinks: _mcpGrantGetLinks,
  attach: _mcpGrantAttach,
  version: '3.4.1',
);

int _mcpGrantEstimateSize(
  McpGrant object,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  var bytesCount = offsets.last;
  bytesCount += 3 + object.clientId.length * 3;
  bytesCount += 3 + object.name.length * 3;
  bytesCount += 3 + object.ownerUserSid.length * 3;
  bytesCount += 3 + object.protectedSecret.length;
  return bytesCount;
}

void _mcpGrantSerialize(
  McpGrant object,
  IsarWriter writer,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  writer.writeLong(offsets[0], object.authorizationEpoch);
  writer.writeString(offsets[1], object.clientId);
  writer.writeLong(offsets[2], object.createdAt);
  writer.writeLong(offsets[3], object.expiresAt);
  writer.writeBool(offsets[4], object.exportPending);
  writer.writeLong(offsets[5], object.grantVersion);
  writer.writeString(offsets[6], object.name);
  writer.writeString(offsets[7], object.ownerUserSid);
  writer.writeByteList(offsets[8], object.protectedSecret);
  writer.writeLong(offsets[9], object.revokedAt);
}

McpGrant _mcpGrantDeserialize(
  Id id,
  IsarReader reader,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  final object = McpGrant();
  object.authorizationEpoch = reader.readLong(offsets[0]);
  object.clientId = reader.readString(offsets[1]);
  object.createdAt = reader.readLong(offsets[2]);
  object.expiresAt = reader.readLong(offsets[3]);
  object.exportPending = reader.readBool(offsets[4]);
  object.grantVersion = reader.readLong(offsets[5]);
  object.id = id;
  object.name = reader.readString(offsets[6]);
  object.ownerUserSid = reader.readString(offsets[7]);
  object.protectedSecret = reader.readByteList(offsets[8]) ?? [];
  object.revokedAt = reader.readLongOrNull(offsets[9]);
  return object;
}

P _mcpGrantDeserializeProp<P>(
  IsarReader reader,
  int propertyId,
  int offset,
  Map<Type, List<int>> allOffsets,
) {
  switch (propertyId) {
    case 0:
      return (reader.readLong(offset)) as P;
    case 1:
      return (reader.readString(offset)) as P;
    case 2:
      return (reader.readLong(offset)) as P;
    case 3:
      return (reader.readLong(offset)) as P;
    case 4:
      return (reader.readBool(offset)) as P;
    case 5:
      return (reader.readLong(offset)) as P;
    case 6:
      return (reader.readString(offset)) as P;
    case 7:
      return (reader.readString(offset)) as P;
    case 8:
      return (reader.readByteList(offset) ?? []) as P;
    case 9:
      return (reader.readLongOrNull(offset)) as P;
    default:
      throw IsarError('Unknown property with id $propertyId');
  }
}

Id _mcpGrantGetId(McpGrant object) {
  return object.id;
}

List<IsarLinkBase<dynamic>> _mcpGrantGetLinks(McpGrant object) {
  return [];
}

void _mcpGrantAttach(IsarCollection<dynamic> col, Id id, McpGrant object) {
  object.id = id;
}

extension McpGrantByIndex on IsarCollection<McpGrant> {
  Future<McpGrant?> getByClientId(String clientId) {
    return getByIndex(r'clientId', [clientId]);
  }

  McpGrant? getByClientIdSync(String clientId) {
    return getByIndexSync(r'clientId', [clientId]);
  }

  Future<bool> deleteByClientId(String clientId) {
    return deleteByIndex(r'clientId', [clientId]);
  }

  bool deleteByClientIdSync(String clientId) {
    return deleteByIndexSync(r'clientId', [clientId]);
  }

  Future<List<McpGrant?>> getAllByClientId(List<String> clientIdValues) {
    final values = clientIdValues.map((e) => [e]).toList();
    return getAllByIndex(r'clientId', values);
  }

  List<McpGrant?> getAllByClientIdSync(List<String> clientIdValues) {
    final values = clientIdValues.map((e) => [e]).toList();
    return getAllByIndexSync(r'clientId', values);
  }

  Future<int> deleteAllByClientId(List<String> clientIdValues) {
    final values = clientIdValues.map((e) => [e]).toList();
    return deleteAllByIndex(r'clientId', values);
  }

  int deleteAllByClientIdSync(List<String> clientIdValues) {
    final values = clientIdValues.map((e) => [e]).toList();
    return deleteAllByIndexSync(r'clientId', values);
  }

  Future<Id> putByClientId(McpGrant object) {
    return putByIndex(r'clientId', object);
  }

  Id putByClientIdSync(McpGrant object, {bool saveLinks = true}) {
    return putByIndexSync(r'clientId', object, saveLinks: saveLinks);
  }

  Future<List<Id>> putAllByClientId(List<McpGrant> objects) {
    return putAllByIndex(r'clientId', objects);
  }

  List<Id> putAllByClientIdSync(
    List<McpGrant> objects, {
    bool saveLinks = true,
  }) {
    return putAllByIndexSync(r'clientId', objects, saveLinks: saveLinks);
  }
}

extension McpGrantQueryWhereSort on QueryBuilder<McpGrant, McpGrant, QWhere> {
  QueryBuilder<McpGrant, McpGrant, QAfterWhere> anyId() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(const IdWhereClause.any());
    });
  }

  QueryBuilder<McpGrant, McpGrant, QAfterWhere> anyExpiresAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        const IndexWhereClause.any(indexName: r'expiresAt'),
      );
    });
  }
}

extension McpGrantQueryWhere on QueryBuilder<McpGrant, McpGrant, QWhereClause> {
  QueryBuilder<McpGrant, McpGrant, QAfterWhereClause> idEqualTo(Id id) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IdWhereClause.between(lower: id, upper: id));
    });
  }

  QueryBuilder<McpGrant, McpGrant, QAfterWhereClause> idNotEqualTo(Id id) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(
              IdWhereClause.lessThan(upper: id, includeUpper: false),
            )
            .addWhereClause(
              IdWhereClause.greaterThan(lower: id, includeLower: false),
            );
      } else {
        return query
            .addWhereClause(
              IdWhereClause.greaterThan(lower: id, includeLower: false),
            )
            .addWhereClause(
              IdWhereClause.lessThan(upper: id, includeUpper: false),
            );
      }
    });
  }

  QueryBuilder<McpGrant, McpGrant, QAfterWhereClause> idGreaterThan(
    Id id, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.greaterThan(lower: id, includeLower: include),
      );
    });
  }

  QueryBuilder<McpGrant, McpGrant, QAfterWhereClause> idLessThan(
    Id id, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.lessThan(upper: id, includeUpper: include),
      );
    });
  }

  QueryBuilder<McpGrant, McpGrant, QAfterWhereClause> idBetween(
    Id lowerId,
    Id upperId, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.between(
          lower: lowerId,
          includeLower: includeLower,
          upper: upperId,
          includeUpper: includeUpper,
        ),
      );
    });
  }

  QueryBuilder<McpGrant, McpGrant, QAfterWhereClause> clientIdEqualTo(
    String clientId,
  ) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IndexWhereClause.equalTo(indexName: r'clientId', value: [clientId]),
      );
    });
  }

  QueryBuilder<McpGrant, McpGrant, QAfterWhereClause> clientIdNotEqualTo(
    String clientId,
  ) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'clientId',
                lower: [],
                upper: [clientId],
                includeUpper: false,
              ),
            )
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'clientId',
                lower: [clientId],
                includeLower: false,
                upper: [],
              ),
            );
      } else {
        return query
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'clientId',
                lower: [clientId],
                includeLower: false,
                upper: [],
              ),
            )
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'clientId',
                lower: [],
                upper: [clientId],
                includeUpper: false,
              ),
            );
      }
    });
  }

  QueryBuilder<McpGrant, McpGrant, QAfterWhereClause> expiresAtEqualTo(
    int expiresAt,
  ) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IndexWhereClause.equalTo(indexName: r'expiresAt', value: [expiresAt]),
      );
    });
  }

  QueryBuilder<McpGrant, McpGrant, QAfterWhereClause> expiresAtNotEqualTo(
    int expiresAt,
  ) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'expiresAt',
                lower: [],
                upper: [expiresAt],
                includeUpper: false,
              ),
            )
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'expiresAt',
                lower: [expiresAt],
                includeLower: false,
                upper: [],
              ),
            );
      } else {
        return query
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'expiresAt',
                lower: [expiresAt],
                includeLower: false,
                upper: [],
              ),
            )
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'expiresAt',
                lower: [],
                upper: [expiresAt],
                includeUpper: false,
              ),
            );
      }
    });
  }

  QueryBuilder<McpGrant, McpGrant, QAfterWhereClause> expiresAtGreaterThan(
    int expiresAt, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IndexWhereClause.between(
          indexName: r'expiresAt',
          lower: [expiresAt],
          includeLower: include,
          upper: [],
        ),
      );
    });
  }

  QueryBuilder<McpGrant, McpGrant, QAfterWhereClause> expiresAtLessThan(
    int expiresAt, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IndexWhereClause.between(
          indexName: r'expiresAt',
          lower: [],
          upper: [expiresAt],
          includeUpper: include,
        ),
      );
    });
  }

  QueryBuilder<McpGrant, McpGrant, QAfterWhereClause> expiresAtBetween(
    int lowerExpiresAt,
    int upperExpiresAt, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IndexWhereClause.between(
          indexName: r'expiresAt',
          lower: [lowerExpiresAt],
          includeLower: includeLower,
          upper: [upperExpiresAt],
          includeUpper: includeUpper,
        ),
      );
    });
  }
}

extension McpGrantQueryFilter
    on QueryBuilder<McpGrant, McpGrant, QFilterCondition> {
  QueryBuilder<McpGrant, McpGrant, QAfterFilterCondition>
  authorizationEpochEqualTo(int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'authorizationEpoch', value: value),
      );
    });
  }

  QueryBuilder<McpGrant, McpGrant, QAfterFilterCondition>
  authorizationEpochGreaterThan(int value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'authorizationEpoch',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<McpGrant, McpGrant, QAfterFilterCondition>
  authorizationEpochLessThan(int value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'authorizationEpoch',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<McpGrant, McpGrant, QAfterFilterCondition>
  authorizationEpochBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'authorizationEpoch',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
        ),
      );
    });
  }

  QueryBuilder<McpGrant, McpGrant, QAfterFilterCondition> clientIdEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'clientId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<McpGrant, McpGrant, QAfterFilterCondition> clientIdGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'clientId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<McpGrant, McpGrant, QAfterFilterCondition> clientIdLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'clientId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<McpGrant, McpGrant, QAfterFilterCondition> clientIdBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'clientId',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<McpGrant, McpGrant, QAfterFilterCondition> clientIdStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.startsWith(
          property: r'clientId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<McpGrant, McpGrant, QAfterFilterCondition> clientIdEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.endsWith(
          property: r'clientId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<McpGrant, McpGrant, QAfterFilterCondition> clientIdContains(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.contains(
          property: r'clientId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<McpGrant, McpGrant, QAfterFilterCondition> clientIdMatches(
    String pattern, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.matches(
          property: r'clientId',
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<McpGrant, McpGrant, QAfterFilterCondition> clientIdIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'clientId', value: ''),
      );
    });
  }

  QueryBuilder<McpGrant, McpGrant, QAfterFilterCondition> clientIdIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(property: r'clientId', value: ''),
      );
    });
  }

  QueryBuilder<McpGrant, McpGrant, QAfterFilterCondition> createdAtEqualTo(
    int value,
  ) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'createdAt', value: value),
      );
    });
  }

  QueryBuilder<McpGrant, McpGrant, QAfterFilterCondition> createdAtGreaterThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'createdAt',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<McpGrant, McpGrant, QAfterFilterCondition> createdAtLessThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'createdAt',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<McpGrant, McpGrant, QAfterFilterCondition> createdAtBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'createdAt',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
        ),
      );
    });
  }

  QueryBuilder<McpGrant, McpGrant, QAfterFilterCondition> expiresAtEqualTo(
    int value,
  ) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'expiresAt', value: value),
      );
    });
  }

  QueryBuilder<McpGrant, McpGrant, QAfterFilterCondition> expiresAtGreaterThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'expiresAt',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<McpGrant, McpGrant, QAfterFilterCondition> expiresAtLessThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'expiresAt',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<McpGrant, McpGrant, QAfterFilterCondition> expiresAtBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'expiresAt',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
        ),
      );
    });
  }

  QueryBuilder<McpGrant, McpGrant, QAfterFilterCondition> exportPendingEqualTo(
    bool value,
  ) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'exportPending', value: value),
      );
    });
  }

  QueryBuilder<McpGrant, McpGrant, QAfterFilterCondition> grantVersionEqualTo(
    int value,
  ) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'grantVersion', value: value),
      );
    });
  }

  QueryBuilder<McpGrant, McpGrant, QAfterFilterCondition>
  grantVersionGreaterThan(int value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'grantVersion',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<McpGrant, McpGrant, QAfterFilterCondition> grantVersionLessThan(
    int value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'grantVersion',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<McpGrant, McpGrant, QAfterFilterCondition> grantVersionBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'grantVersion',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
        ),
      );
    });
  }

  QueryBuilder<McpGrant, McpGrant, QAfterFilterCondition> idEqualTo(Id value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'id', value: value),
      );
    });
  }

  QueryBuilder<McpGrant, McpGrant, QAfterFilterCondition> idGreaterThan(
    Id value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'id',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<McpGrant, McpGrant, QAfterFilterCondition> idLessThan(
    Id value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'id',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<McpGrant, McpGrant, QAfterFilterCondition> idBetween(
    Id lower,
    Id upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'id',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
        ),
      );
    });
  }

  QueryBuilder<McpGrant, McpGrant, QAfterFilterCondition> nameEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'name',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<McpGrant, McpGrant, QAfterFilterCondition> nameGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'name',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<McpGrant, McpGrant, QAfterFilterCondition> nameLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'name',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<McpGrant, McpGrant, QAfterFilterCondition> nameBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'name',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<McpGrant, McpGrant, QAfterFilterCondition> nameStartsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.startsWith(
          property: r'name',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<McpGrant, McpGrant, QAfterFilterCondition> nameEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.endsWith(
          property: r'name',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<McpGrant, McpGrant, QAfterFilterCondition> nameContains(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.contains(
          property: r'name',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<McpGrant, McpGrant, QAfterFilterCondition> nameMatches(
    String pattern, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.matches(
          property: r'name',
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<McpGrant, McpGrant, QAfterFilterCondition> nameIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'name', value: ''),
      );
    });
  }

  QueryBuilder<McpGrant, McpGrant, QAfterFilterCondition> nameIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(property: r'name', value: ''),
      );
    });
  }

  QueryBuilder<McpGrant, McpGrant, QAfterFilterCondition> ownerUserSidEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'ownerUserSid',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<McpGrant, McpGrant, QAfterFilterCondition>
  ownerUserSidGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'ownerUserSid',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<McpGrant, McpGrant, QAfterFilterCondition> ownerUserSidLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'ownerUserSid',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<McpGrant, McpGrant, QAfterFilterCondition> ownerUserSidBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'ownerUserSid',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<McpGrant, McpGrant, QAfterFilterCondition>
  ownerUserSidStartsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.startsWith(
          property: r'ownerUserSid',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<McpGrant, McpGrant, QAfterFilterCondition> ownerUserSidEndsWith(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.endsWith(
          property: r'ownerUserSid',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<McpGrant, McpGrant, QAfterFilterCondition> ownerUserSidContains(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.contains(
          property: r'ownerUserSid',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<McpGrant, McpGrant, QAfterFilterCondition> ownerUserSidMatches(
    String pattern, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.matches(
          property: r'ownerUserSid',
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<McpGrant, McpGrant, QAfterFilterCondition>
  ownerUserSidIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'ownerUserSid', value: ''),
      );
    });
  }

  QueryBuilder<McpGrant, McpGrant, QAfterFilterCondition>
  ownerUserSidIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(property: r'ownerUserSid', value: ''),
      );
    });
  }

  QueryBuilder<McpGrant, McpGrant, QAfterFilterCondition>
  protectedSecretElementEqualTo(int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'protectedSecret', value: value),
      );
    });
  }

  QueryBuilder<McpGrant, McpGrant, QAfterFilterCondition>
  protectedSecretElementGreaterThan(int value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'protectedSecret',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<McpGrant, McpGrant, QAfterFilterCondition>
  protectedSecretElementLessThan(int value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'protectedSecret',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<McpGrant, McpGrant, QAfterFilterCondition>
  protectedSecretElementBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'protectedSecret',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
        ),
      );
    });
  }

  QueryBuilder<McpGrant, McpGrant, QAfterFilterCondition>
  protectedSecretLengthEqualTo(int length) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(r'protectedSecret', length, true, length, true);
    });
  }

  QueryBuilder<McpGrant, McpGrant, QAfterFilterCondition>
  protectedSecretIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(r'protectedSecret', 0, true, 0, true);
    });
  }

  QueryBuilder<McpGrant, McpGrant, QAfterFilterCondition>
  protectedSecretIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(r'protectedSecret', 0, false, 999999, true);
    });
  }

  QueryBuilder<McpGrant, McpGrant, QAfterFilterCondition>
  protectedSecretLengthLessThan(int length, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(r'protectedSecret', 0, true, length, include);
    });
  }

  QueryBuilder<McpGrant, McpGrant, QAfterFilterCondition>
  protectedSecretLengthGreaterThan(int length, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'protectedSecret',
        length,
        include,
        999999,
        true,
      );
    });
  }

  QueryBuilder<McpGrant, McpGrant, QAfterFilterCondition>
  protectedSecretLengthBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'protectedSecret',
        lower,
        includeLower,
        upper,
        includeUpper,
      );
    });
  }

  QueryBuilder<McpGrant, McpGrant, QAfterFilterCondition> revokedAtIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNull(property: r'revokedAt'),
      );
    });
  }

  QueryBuilder<McpGrant, McpGrant, QAfterFilterCondition> revokedAtIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNotNull(property: r'revokedAt'),
      );
    });
  }

  QueryBuilder<McpGrant, McpGrant, QAfterFilterCondition> revokedAtEqualTo(
    int? value,
  ) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'revokedAt', value: value),
      );
    });
  }

  QueryBuilder<McpGrant, McpGrant, QAfterFilterCondition> revokedAtGreaterThan(
    int? value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'revokedAt',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<McpGrant, McpGrant, QAfterFilterCondition> revokedAtLessThan(
    int? value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'revokedAt',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<McpGrant, McpGrant, QAfterFilterCondition> revokedAtBetween(
    int? lower,
    int? upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'revokedAt',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
        ),
      );
    });
  }
}

extension McpGrantQueryObject
    on QueryBuilder<McpGrant, McpGrant, QFilterCondition> {}

extension McpGrantQueryLinks
    on QueryBuilder<McpGrant, McpGrant, QFilterCondition> {}

extension McpGrantQuerySortBy on QueryBuilder<McpGrant, McpGrant, QSortBy> {
  QueryBuilder<McpGrant, McpGrant, QAfterSortBy> sortByAuthorizationEpoch() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'authorizationEpoch', Sort.asc);
    });
  }

  QueryBuilder<McpGrant, McpGrant, QAfterSortBy>
  sortByAuthorizationEpochDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'authorizationEpoch', Sort.desc);
    });
  }

  QueryBuilder<McpGrant, McpGrant, QAfterSortBy> sortByClientId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'clientId', Sort.asc);
    });
  }

  QueryBuilder<McpGrant, McpGrant, QAfterSortBy> sortByClientIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'clientId', Sort.desc);
    });
  }

  QueryBuilder<McpGrant, McpGrant, QAfterSortBy> sortByCreatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'createdAt', Sort.asc);
    });
  }

  QueryBuilder<McpGrant, McpGrant, QAfterSortBy> sortByCreatedAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'createdAt', Sort.desc);
    });
  }

  QueryBuilder<McpGrant, McpGrant, QAfterSortBy> sortByExpiresAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'expiresAt', Sort.asc);
    });
  }

  QueryBuilder<McpGrant, McpGrant, QAfterSortBy> sortByExpiresAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'expiresAt', Sort.desc);
    });
  }

  QueryBuilder<McpGrant, McpGrant, QAfterSortBy> sortByExportPending() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'exportPending', Sort.asc);
    });
  }

  QueryBuilder<McpGrant, McpGrant, QAfterSortBy> sortByExportPendingDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'exportPending', Sort.desc);
    });
  }

  QueryBuilder<McpGrant, McpGrant, QAfterSortBy> sortByGrantVersion() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'grantVersion', Sort.asc);
    });
  }

  QueryBuilder<McpGrant, McpGrant, QAfterSortBy> sortByGrantVersionDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'grantVersion', Sort.desc);
    });
  }

  QueryBuilder<McpGrant, McpGrant, QAfterSortBy> sortByName() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'name', Sort.asc);
    });
  }

  QueryBuilder<McpGrant, McpGrant, QAfterSortBy> sortByNameDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'name', Sort.desc);
    });
  }

  QueryBuilder<McpGrant, McpGrant, QAfterSortBy> sortByOwnerUserSid() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'ownerUserSid', Sort.asc);
    });
  }

  QueryBuilder<McpGrant, McpGrant, QAfterSortBy> sortByOwnerUserSidDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'ownerUserSid', Sort.desc);
    });
  }

  QueryBuilder<McpGrant, McpGrant, QAfterSortBy> sortByRevokedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'revokedAt', Sort.asc);
    });
  }

  QueryBuilder<McpGrant, McpGrant, QAfterSortBy> sortByRevokedAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'revokedAt', Sort.desc);
    });
  }
}

extension McpGrantQuerySortThenBy
    on QueryBuilder<McpGrant, McpGrant, QSortThenBy> {
  QueryBuilder<McpGrant, McpGrant, QAfterSortBy> thenByAuthorizationEpoch() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'authorizationEpoch', Sort.asc);
    });
  }

  QueryBuilder<McpGrant, McpGrant, QAfterSortBy>
  thenByAuthorizationEpochDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'authorizationEpoch', Sort.desc);
    });
  }

  QueryBuilder<McpGrant, McpGrant, QAfterSortBy> thenByClientId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'clientId', Sort.asc);
    });
  }

  QueryBuilder<McpGrant, McpGrant, QAfterSortBy> thenByClientIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'clientId', Sort.desc);
    });
  }

  QueryBuilder<McpGrant, McpGrant, QAfterSortBy> thenByCreatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'createdAt', Sort.asc);
    });
  }

  QueryBuilder<McpGrant, McpGrant, QAfterSortBy> thenByCreatedAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'createdAt', Sort.desc);
    });
  }

  QueryBuilder<McpGrant, McpGrant, QAfterSortBy> thenByExpiresAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'expiresAt', Sort.asc);
    });
  }

  QueryBuilder<McpGrant, McpGrant, QAfterSortBy> thenByExpiresAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'expiresAt', Sort.desc);
    });
  }

  QueryBuilder<McpGrant, McpGrant, QAfterSortBy> thenByExportPending() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'exportPending', Sort.asc);
    });
  }

  QueryBuilder<McpGrant, McpGrant, QAfterSortBy> thenByExportPendingDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'exportPending', Sort.desc);
    });
  }

  QueryBuilder<McpGrant, McpGrant, QAfterSortBy> thenByGrantVersion() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'grantVersion', Sort.asc);
    });
  }

  QueryBuilder<McpGrant, McpGrant, QAfterSortBy> thenByGrantVersionDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'grantVersion', Sort.desc);
    });
  }

  QueryBuilder<McpGrant, McpGrant, QAfterSortBy> thenById() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.asc);
    });
  }

  QueryBuilder<McpGrant, McpGrant, QAfterSortBy> thenByIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.desc);
    });
  }

  QueryBuilder<McpGrant, McpGrant, QAfterSortBy> thenByName() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'name', Sort.asc);
    });
  }

  QueryBuilder<McpGrant, McpGrant, QAfterSortBy> thenByNameDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'name', Sort.desc);
    });
  }

  QueryBuilder<McpGrant, McpGrant, QAfterSortBy> thenByOwnerUserSid() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'ownerUserSid', Sort.asc);
    });
  }

  QueryBuilder<McpGrant, McpGrant, QAfterSortBy> thenByOwnerUserSidDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'ownerUserSid', Sort.desc);
    });
  }

  QueryBuilder<McpGrant, McpGrant, QAfterSortBy> thenByRevokedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'revokedAt', Sort.asc);
    });
  }

  QueryBuilder<McpGrant, McpGrant, QAfterSortBy> thenByRevokedAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'revokedAt', Sort.desc);
    });
  }
}

extension McpGrantQueryWhereDistinct
    on QueryBuilder<McpGrant, McpGrant, QDistinct> {
  QueryBuilder<McpGrant, McpGrant, QDistinct> distinctByAuthorizationEpoch() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'authorizationEpoch');
    });
  }

  QueryBuilder<McpGrant, McpGrant, QDistinct> distinctByClientId({
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'clientId', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<McpGrant, McpGrant, QDistinct> distinctByCreatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'createdAt');
    });
  }

  QueryBuilder<McpGrant, McpGrant, QDistinct> distinctByExpiresAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'expiresAt');
    });
  }

  QueryBuilder<McpGrant, McpGrant, QDistinct> distinctByExportPending() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'exportPending');
    });
  }

  QueryBuilder<McpGrant, McpGrant, QDistinct> distinctByGrantVersion() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'grantVersion');
    });
  }

  QueryBuilder<McpGrant, McpGrant, QDistinct> distinctByName({
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'name', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<McpGrant, McpGrant, QDistinct> distinctByOwnerUserSid({
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'ownerUserSid', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<McpGrant, McpGrant, QDistinct> distinctByProtectedSecret() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'protectedSecret');
    });
  }

  QueryBuilder<McpGrant, McpGrant, QDistinct> distinctByRevokedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'revokedAt');
    });
  }
}

extension McpGrantQueryProperty
    on QueryBuilder<McpGrant, McpGrant, QQueryProperty> {
  QueryBuilder<McpGrant, int, QQueryOperations> idProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'id');
    });
  }

  QueryBuilder<McpGrant, int, QQueryOperations> authorizationEpochProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'authorizationEpoch');
    });
  }

  QueryBuilder<McpGrant, String, QQueryOperations> clientIdProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'clientId');
    });
  }

  QueryBuilder<McpGrant, int, QQueryOperations> createdAtProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'createdAt');
    });
  }

  QueryBuilder<McpGrant, int, QQueryOperations> expiresAtProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'expiresAt');
    });
  }

  QueryBuilder<McpGrant, bool, QQueryOperations> exportPendingProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'exportPending');
    });
  }

  QueryBuilder<McpGrant, int, QQueryOperations> grantVersionProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'grantVersion');
    });
  }

  QueryBuilder<McpGrant, String, QQueryOperations> nameProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'name');
    });
  }

  QueryBuilder<McpGrant, String, QQueryOperations> ownerUserSidProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'ownerUserSid');
    });
  }

  QueryBuilder<McpGrant, List<int>, QQueryOperations>
  protectedSecretProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'protectedSecret');
    });
  }

  QueryBuilder<McpGrant, int?, QQueryOperations> revokedAtProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'revokedAt');
    });
  }
}

// coverage:ignore-file
// ignore_for_file: duplicate_ignore, non_constant_identifier_names, constant_identifier_names, invalid_use_of_protected_member, unnecessary_cast, prefer_const_constructors, lines_longer_than_80_chars, require_trailing_commas, inference_failure_on_function_invocation, unnecessary_parenthesis, unnecessary_raw_strings, unnecessary_null_checks, join_return_with_assignment, prefer_final_locals, avoid_js_rounded_ints, avoid_positional_boolean_parameters, always_specify_types, experimental_member_use

extension GetMutationReceiptCollection on Isar {
  IsarCollection<MutationReceipt> get mutationReceipts => this.collection();
}

const MutationReceiptSchema = CollectionSchema(
  name: r'MutationReceipt',
  id: 5484880928770155821,
  properties: {
    r'clientId': PropertySchema(
      id: 0,
      name: r'clientId',
      type: IsarType.string,
    ),
    r'committedDataRevision': PropertySchema(
      id: 1,
      name: r'committedDataRevision',
      type: IsarType.long,
    ),
    r'createdAt': PropertySchema(
      id: 2,
      name: r'createdAt',
      type: IsarType.long,
    ),
    r'entityIds': PropertySchema(
      id: 3,
      name: r'entityIds',
      type: IsarType.stringList,
    ),
    r'entityRevisions': PropertySchema(
      id: 4,
      name: r'entityRevisions',
      type: IsarType.longList,
    ),
    r'expiresAt': PropertySchema(
      id: 5,
      name: r'expiresAt',
      type: IsarType.long,
    ),
    r'method': PropertySchema(id: 6, name: r'method', type: IsarType.string),
    r'mutationId': PropertySchema(
      id: 7,
      name: r'mutationId',
      type: IsarType.string,
    ),
    r'payloadHmac': PropertySchema(
      id: 8,
      name: r'payloadHmac',
      type: IsarType.byteList,
    ),
    r'resultCode': PropertySchema(
      id: 9,
      name: r'resultCode',
      type: IsarType.string,
    ),
  },

  estimateSize: _mutationReceiptEstimateSize,
  serialize: _mutationReceiptSerialize,
  deserialize: _mutationReceiptDeserialize,
  deserializeProp: _mutationReceiptDeserializeProp,
  idName: r'id',
  indexes: {
    r'clientId_mutationId': IndexSchema(
      id: 2538256626640005166,
      name: r'clientId_mutationId',
      unique: true,
      replace: false,
      properties: [
        IndexPropertySchema(
          name: r'clientId',
          type: IndexType.hash,
          caseSensitive: true,
        ),
        IndexPropertySchema(
          name: r'mutationId',
          type: IndexType.hash,
          caseSensitive: true,
        ),
      ],
    ),
    r'expiresAt': IndexSchema(
      id: 4994901953235663716,
      name: r'expiresAt',
      unique: false,
      replace: false,
      properties: [
        IndexPropertySchema(
          name: r'expiresAt',
          type: IndexType.value,
          caseSensitive: false,
        ),
      ],
    ),
  },
  links: {},
  embeddedSchemas: {},

  getId: _mutationReceiptGetId,
  getLinks: _mutationReceiptGetLinks,
  attach: _mutationReceiptAttach,
  version: '3.4.1',
);

int _mutationReceiptEstimateSize(
  MutationReceipt object,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  var bytesCount = offsets.last;
  bytesCount += 3 + object.clientId.length * 3;
  bytesCount += 3 + object.entityIds.length * 3;
  {
    for (var i = 0; i < object.entityIds.length; i++) {
      final value = object.entityIds[i];
      bytesCount += value.length * 3;
    }
  }
  bytesCount += 3 + object.entityRevisions.length * 8;
  bytesCount += 3 + object.method.length * 3;
  bytesCount += 3 + object.mutationId.length * 3;
  bytesCount += 3 + object.payloadHmac.length;
  bytesCount += 3 + object.resultCode.length * 3;
  return bytesCount;
}

void _mutationReceiptSerialize(
  MutationReceipt object,
  IsarWriter writer,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  writer.writeString(offsets[0], object.clientId);
  writer.writeLong(offsets[1], object.committedDataRevision);
  writer.writeLong(offsets[2], object.createdAt);
  writer.writeStringList(offsets[3], object.entityIds);
  writer.writeLongList(offsets[4], object.entityRevisions);
  writer.writeLong(offsets[5], object.expiresAt);
  writer.writeString(offsets[6], object.method);
  writer.writeString(offsets[7], object.mutationId);
  writer.writeByteList(offsets[8], object.payloadHmac);
  writer.writeString(offsets[9], object.resultCode);
}

MutationReceipt _mutationReceiptDeserialize(
  Id id,
  IsarReader reader,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  final object = MutationReceipt();
  object.clientId = reader.readString(offsets[0]);
  object.committedDataRevision = reader.readLong(offsets[1]);
  object.createdAt = reader.readLong(offsets[2]);
  object.entityIds = reader.readStringList(offsets[3]) ?? [];
  object.entityRevisions = reader.readLongList(offsets[4]) ?? [];
  object.expiresAt = reader.readLong(offsets[5]);
  object.id = id;
  object.method = reader.readString(offsets[6]);
  object.mutationId = reader.readString(offsets[7]);
  object.payloadHmac = reader.readByteList(offsets[8]) ?? [];
  object.resultCode = reader.readString(offsets[9]);
  return object;
}

P _mutationReceiptDeserializeProp<P>(
  IsarReader reader,
  int propertyId,
  int offset,
  Map<Type, List<int>> allOffsets,
) {
  switch (propertyId) {
    case 0:
      return (reader.readString(offset)) as P;
    case 1:
      return (reader.readLong(offset)) as P;
    case 2:
      return (reader.readLong(offset)) as P;
    case 3:
      return (reader.readStringList(offset) ?? []) as P;
    case 4:
      return (reader.readLongList(offset) ?? []) as P;
    case 5:
      return (reader.readLong(offset)) as P;
    case 6:
      return (reader.readString(offset)) as P;
    case 7:
      return (reader.readString(offset)) as P;
    case 8:
      return (reader.readByteList(offset) ?? []) as P;
    case 9:
      return (reader.readString(offset)) as P;
    default:
      throw IsarError('Unknown property with id $propertyId');
  }
}

Id _mutationReceiptGetId(MutationReceipt object) {
  return object.id;
}

List<IsarLinkBase<dynamic>> _mutationReceiptGetLinks(MutationReceipt object) {
  return [];
}

void _mutationReceiptAttach(
  IsarCollection<dynamic> col,
  Id id,
  MutationReceipt object,
) {
  object.id = id;
}

extension MutationReceiptByIndex on IsarCollection<MutationReceipt> {
  Future<MutationReceipt?> getByClientIdMutationId(
    String clientId,
    String mutationId,
  ) {
    return getByIndex(r'clientId_mutationId', [clientId, mutationId]);
  }

  MutationReceipt? getByClientIdMutationIdSync(
    String clientId,
    String mutationId,
  ) {
    return getByIndexSync(r'clientId_mutationId', [clientId, mutationId]);
  }

  Future<bool> deleteByClientIdMutationId(String clientId, String mutationId) {
    return deleteByIndex(r'clientId_mutationId', [clientId, mutationId]);
  }

  bool deleteByClientIdMutationIdSync(String clientId, String mutationId) {
    return deleteByIndexSync(r'clientId_mutationId', [clientId, mutationId]);
  }

  Future<List<MutationReceipt?>> getAllByClientIdMutationId(
    List<String> clientIdValues,
    List<String> mutationIdValues,
  ) {
    final len = clientIdValues.length;
    assert(
      mutationIdValues.length == len,
      'All index values must have the same length',
    );
    final values = <List<dynamic>>[];
    for (var i = 0; i < len; i++) {
      values.add([clientIdValues[i], mutationIdValues[i]]);
    }

    return getAllByIndex(r'clientId_mutationId', values);
  }

  List<MutationReceipt?> getAllByClientIdMutationIdSync(
    List<String> clientIdValues,
    List<String> mutationIdValues,
  ) {
    final len = clientIdValues.length;
    assert(
      mutationIdValues.length == len,
      'All index values must have the same length',
    );
    final values = <List<dynamic>>[];
    for (var i = 0; i < len; i++) {
      values.add([clientIdValues[i], mutationIdValues[i]]);
    }

    return getAllByIndexSync(r'clientId_mutationId', values);
  }

  Future<int> deleteAllByClientIdMutationId(
    List<String> clientIdValues,
    List<String> mutationIdValues,
  ) {
    final len = clientIdValues.length;
    assert(
      mutationIdValues.length == len,
      'All index values must have the same length',
    );
    final values = <List<dynamic>>[];
    for (var i = 0; i < len; i++) {
      values.add([clientIdValues[i], mutationIdValues[i]]);
    }

    return deleteAllByIndex(r'clientId_mutationId', values);
  }

  int deleteAllByClientIdMutationIdSync(
    List<String> clientIdValues,
    List<String> mutationIdValues,
  ) {
    final len = clientIdValues.length;
    assert(
      mutationIdValues.length == len,
      'All index values must have the same length',
    );
    final values = <List<dynamic>>[];
    for (var i = 0; i < len; i++) {
      values.add([clientIdValues[i], mutationIdValues[i]]);
    }

    return deleteAllByIndexSync(r'clientId_mutationId', values);
  }

  Future<Id> putByClientIdMutationId(MutationReceipt object) {
    return putByIndex(r'clientId_mutationId', object);
  }

  Id putByClientIdMutationIdSync(
    MutationReceipt object, {
    bool saveLinks = true,
  }) {
    return putByIndexSync(r'clientId_mutationId', object, saveLinks: saveLinks);
  }

  Future<List<Id>> putAllByClientIdMutationId(List<MutationReceipt> objects) {
    return putAllByIndex(r'clientId_mutationId', objects);
  }

  List<Id> putAllByClientIdMutationIdSync(
    List<MutationReceipt> objects, {
    bool saveLinks = true,
  }) {
    return putAllByIndexSync(
      r'clientId_mutationId',
      objects,
      saveLinks: saveLinks,
    );
  }
}

extension MutationReceiptQueryWhereSort
    on QueryBuilder<MutationReceipt, MutationReceipt, QWhere> {
  QueryBuilder<MutationReceipt, MutationReceipt, QAfterWhere> anyId() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(const IdWhereClause.any());
    });
  }

  QueryBuilder<MutationReceipt, MutationReceipt, QAfterWhere> anyExpiresAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        const IndexWhereClause.any(indexName: r'expiresAt'),
      );
    });
  }
}

extension MutationReceiptQueryWhere
    on QueryBuilder<MutationReceipt, MutationReceipt, QWhereClause> {
  QueryBuilder<MutationReceipt, MutationReceipt, QAfterWhereClause> idEqualTo(
    Id id,
  ) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IdWhereClause.between(lower: id, upper: id));
    });
  }

  QueryBuilder<MutationReceipt, MutationReceipt, QAfterWhereClause>
  idNotEqualTo(Id id) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(
              IdWhereClause.lessThan(upper: id, includeUpper: false),
            )
            .addWhereClause(
              IdWhereClause.greaterThan(lower: id, includeLower: false),
            );
      } else {
        return query
            .addWhereClause(
              IdWhereClause.greaterThan(lower: id, includeLower: false),
            )
            .addWhereClause(
              IdWhereClause.lessThan(upper: id, includeUpper: false),
            );
      }
    });
  }

  QueryBuilder<MutationReceipt, MutationReceipt, QAfterWhereClause>
  idGreaterThan(Id id, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.greaterThan(lower: id, includeLower: include),
      );
    });
  }

  QueryBuilder<MutationReceipt, MutationReceipt, QAfterWhereClause> idLessThan(
    Id id, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.lessThan(upper: id, includeUpper: include),
      );
    });
  }

  QueryBuilder<MutationReceipt, MutationReceipt, QAfterWhereClause> idBetween(
    Id lowerId,
    Id upperId, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.between(
          lower: lowerId,
          includeLower: includeLower,
          upper: upperId,
          includeUpper: includeUpper,
        ),
      );
    });
  }

  QueryBuilder<MutationReceipt, MutationReceipt, QAfterWhereClause>
  clientIdEqualToAnyMutationId(String clientId) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IndexWhereClause.equalTo(
          indexName: r'clientId_mutationId',
          value: [clientId],
        ),
      );
    });
  }

  QueryBuilder<MutationReceipt, MutationReceipt, QAfterWhereClause>
  clientIdNotEqualToAnyMutationId(String clientId) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'clientId_mutationId',
                lower: [],
                upper: [clientId],
                includeUpper: false,
              ),
            )
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'clientId_mutationId',
                lower: [clientId],
                includeLower: false,
                upper: [],
              ),
            );
      } else {
        return query
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'clientId_mutationId',
                lower: [clientId],
                includeLower: false,
                upper: [],
              ),
            )
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'clientId_mutationId',
                lower: [],
                upper: [clientId],
                includeUpper: false,
              ),
            );
      }
    });
  }

  QueryBuilder<MutationReceipt, MutationReceipt, QAfterWhereClause>
  clientIdMutationIdEqualTo(String clientId, String mutationId) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IndexWhereClause.equalTo(
          indexName: r'clientId_mutationId',
          value: [clientId, mutationId],
        ),
      );
    });
  }

  QueryBuilder<MutationReceipt, MutationReceipt, QAfterWhereClause>
  clientIdEqualToMutationIdNotEqualTo(String clientId, String mutationId) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'clientId_mutationId',
                lower: [clientId],
                upper: [clientId, mutationId],
                includeUpper: false,
              ),
            )
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'clientId_mutationId',
                lower: [clientId, mutationId],
                includeLower: false,
                upper: [clientId],
              ),
            );
      } else {
        return query
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'clientId_mutationId',
                lower: [clientId, mutationId],
                includeLower: false,
                upper: [clientId],
              ),
            )
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'clientId_mutationId',
                lower: [clientId],
                upper: [clientId, mutationId],
                includeUpper: false,
              ),
            );
      }
    });
  }

  QueryBuilder<MutationReceipt, MutationReceipt, QAfterWhereClause>
  expiresAtEqualTo(int expiresAt) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IndexWhereClause.equalTo(indexName: r'expiresAt', value: [expiresAt]),
      );
    });
  }

  QueryBuilder<MutationReceipt, MutationReceipt, QAfterWhereClause>
  expiresAtNotEqualTo(int expiresAt) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'expiresAt',
                lower: [],
                upper: [expiresAt],
                includeUpper: false,
              ),
            )
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'expiresAt',
                lower: [expiresAt],
                includeLower: false,
                upper: [],
              ),
            );
      } else {
        return query
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'expiresAt',
                lower: [expiresAt],
                includeLower: false,
                upper: [],
              ),
            )
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'expiresAt',
                lower: [],
                upper: [expiresAt],
                includeUpper: false,
              ),
            );
      }
    });
  }

  QueryBuilder<MutationReceipt, MutationReceipt, QAfterWhereClause>
  expiresAtGreaterThan(int expiresAt, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IndexWhereClause.between(
          indexName: r'expiresAt',
          lower: [expiresAt],
          includeLower: include,
          upper: [],
        ),
      );
    });
  }

  QueryBuilder<MutationReceipt, MutationReceipt, QAfterWhereClause>
  expiresAtLessThan(int expiresAt, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IndexWhereClause.between(
          indexName: r'expiresAt',
          lower: [],
          upper: [expiresAt],
          includeUpper: include,
        ),
      );
    });
  }

  QueryBuilder<MutationReceipt, MutationReceipt, QAfterWhereClause>
  expiresAtBetween(
    int lowerExpiresAt,
    int upperExpiresAt, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IndexWhereClause.between(
          indexName: r'expiresAt',
          lower: [lowerExpiresAt],
          includeLower: includeLower,
          upper: [upperExpiresAt],
          includeUpper: includeUpper,
        ),
      );
    });
  }
}

extension MutationReceiptQueryFilter
    on QueryBuilder<MutationReceipt, MutationReceipt, QFilterCondition> {
  QueryBuilder<MutationReceipt, MutationReceipt, QAfterFilterCondition>
  clientIdEqualTo(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'clientId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<MutationReceipt, MutationReceipt, QAfterFilterCondition>
  clientIdGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'clientId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<MutationReceipt, MutationReceipt, QAfterFilterCondition>
  clientIdLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'clientId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<MutationReceipt, MutationReceipt, QAfterFilterCondition>
  clientIdBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'clientId',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<MutationReceipt, MutationReceipt, QAfterFilterCondition>
  clientIdStartsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.startsWith(
          property: r'clientId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<MutationReceipt, MutationReceipt, QAfterFilterCondition>
  clientIdEndsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.endsWith(
          property: r'clientId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<MutationReceipt, MutationReceipt, QAfterFilterCondition>
  clientIdContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.contains(
          property: r'clientId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<MutationReceipt, MutationReceipt, QAfterFilterCondition>
  clientIdMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.matches(
          property: r'clientId',
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<MutationReceipt, MutationReceipt, QAfterFilterCondition>
  clientIdIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'clientId', value: ''),
      );
    });
  }

  QueryBuilder<MutationReceipt, MutationReceipt, QAfterFilterCondition>
  clientIdIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(property: r'clientId', value: ''),
      );
    });
  }

  QueryBuilder<MutationReceipt, MutationReceipt, QAfterFilterCondition>
  committedDataRevisionEqualTo(int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'committedDataRevision',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<MutationReceipt, MutationReceipt, QAfterFilterCondition>
  committedDataRevisionGreaterThan(int value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'committedDataRevision',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<MutationReceipt, MutationReceipt, QAfterFilterCondition>
  committedDataRevisionLessThan(int value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'committedDataRevision',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<MutationReceipt, MutationReceipt, QAfterFilterCondition>
  committedDataRevisionBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'committedDataRevision',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
        ),
      );
    });
  }

  QueryBuilder<MutationReceipt, MutationReceipt, QAfterFilterCondition>
  createdAtEqualTo(int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'createdAt', value: value),
      );
    });
  }

  QueryBuilder<MutationReceipt, MutationReceipt, QAfterFilterCondition>
  createdAtGreaterThan(int value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'createdAt',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<MutationReceipt, MutationReceipt, QAfterFilterCondition>
  createdAtLessThan(int value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'createdAt',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<MutationReceipt, MutationReceipt, QAfterFilterCondition>
  createdAtBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'createdAt',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
        ),
      );
    });
  }

  QueryBuilder<MutationReceipt, MutationReceipt, QAfterFilterCondition>
  entityIdsElementEqualTo(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'entityIds',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<MutationReceipt, MutationReceipt, QAfterFilterCondition>
  entityIdsElementGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'entityIds',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<MutationReceipt, MutationReceipt, QAfterFilterCondition>
  entityIdsElementLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'entityIds',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<MutationReceipt, MutationReceipt, QAfterFilterCondition>
  entityIdsElementBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'entityIds',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<MutationReceipt, MutationReceipt, QAfterFilterCondition>
  entityIdsElementStartsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.startsWith(
          property: r'entityIds',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<MutationReceipt, MutationReceipt, QAfterFilterCondition>
  entityIdsElementEndsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.endsWith(
          property: r'entityIds',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<MutationReceipt, MutationReceipt, QAfterFilterCondition>
  entityIdsElementContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.contains(
          property: r'entityIds',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<MutationReceipt, MutationReceipt, QAfterFilterCondition>
  entityIdsElementMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.matches(
          property: r'entityIds',
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<MutationReceipt, MutationReceipt, QAfterFilterCondition>
  entityIdsElementIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'entityIds', value: ''),
      );
    });
  }

  QueryBuilder<MutationReceipt, MutationReceipt, QAfterFilterCondition>
  entityIdsElementIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(property: r'entityIds', value: ''),
      );
    });
  }

  QueryBuilder<MutationReceipt, MutationReceipt, QAfterFilterCondition>
  entityIdsLengthEqualTo(int length) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(r'entityIds', length, true, length, true);
    });
  }

  QueryBuilder<MutationReceipt, MutationReceipt, QAfterFilterCondition>
  entityIdsIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(r'entityIds', 0, true, 0, true);
    });
  }

  QueryBuilder<MutationReceipt, MutationReceipt, QAfterFilterCondition>
  entityIdsIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(r'entityIds', 0, false, 999999, true);
    });
  }

  QueryBuilder<MutationReceipt, MutationReceipt, QAfterFilterCondition>
  entityIdsLengthLessThan(int length, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(r'entityIds', 0, true, length, include);
    });
  }

  QueryBuilder<MutationReceipt, MutationReceipt, QAfterFilterCondition>
  entityIdsLengthGreaterThan(int length, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(r'entityIds', length, include, 999999, true);
    });
  }

  QueryBuilder<MutationReceipt, MutationReceipt, QAfterFilterCondition>
  entityIdsLengthBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'entityIds',
        lower,
        includeLower,
        upper,
        includeUpper,
      );
    });
  }

  QueryBuilder<MutationReceipt, MutationReceipt, QAfterFilterCondition>
  entityRevisionsElementEqualTo(int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'entityRevisions', value: value),
      );
    });
  }

  QueryBuilder<MutationReceipt, MutationReceipt, QAfterFilterCondition>
  entityRevisionsElementGreaterThan(int value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'entityRevisions',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<MutationReceipt, MutationReceipt, QAfterFilterCondition>
  entityRevisionsElementLessThan(int value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'entityRevisions',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<MutationReceipt, MutationReceipt, QAfterFilterCondition>
  entityRevisionsElementBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'entityRevisions',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
        ),
      );
    });
  }

  QueryBuilder<MutationReceipt, MutationReceipt, QAfterFilterCondition>
  entityRevisionsLengthEqualTo(int length) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(r'entityRevisions', length, true, length, true);
    });
  }

  QueryBuilder<MutationReceipt, MutationReceipt, QAfterFilterCondition>
  entityRevisionsIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(r'entityRevisions', 0, true, 0, true);
    });
  }

  QueryBuilder<MutationReceipt, MutationReceipt, QAfterFilterCondition>
  entityRevisionsIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(r'entityRevisions', 0, false, 999999, true);
    });
  }

  QueryBuilder<MutationReceipt, MutationReceipt, QAfterFilterCondition>
  entityRevisionsLengthLessThan(int length, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(r'entityRevisions', 0, true, length, include);
    });
  }

  QueryBuilder<MutationReceipt, MutationReceipt, QAfterFilterCondition>
  entityRevisionsLengthGreaterThan(int length, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'entityRevisions',
        length,
        include,
        999999,
        true,
      );
    });
  }

  QueryBuilder<MutationReceipt, MutationReceipt, QAfterFilterCondition>
  entityRevisionsLengthBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'entityRevisions',
        lower,
        includeLower,
        upper,
        includeUpper,
      );
    });
  }

  QueryBuilder<MutationReceipt, MutationReceipt, QAfterFilterCondition>
  expiresAtEqualTo(int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'expiresAt', value: value),
      );
    });
  }

  QueryBuilder<MutationReceipt, MutationReceipt, QAfterFilterCondition>
  expiresAtGreaterThan(int value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'expiresAt',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<MutationReceipt, MutationReceipt, QAfterFilterCondition>
  expiresAtLessThan(int value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'expiresAt',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<MutationReceipt, MutationReceipt, QAfterFilterCondition>
  expiresAtBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'expiresAt',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
        ),
      );
    });
  }

  QueryBuilder<MutationReceipt, MutationReceipt, QAfterFilterCondition>
  idEqualTo(Id value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'id', value: value),
      );
    });
  }

  QueryBuilder<MutationReceipt, MutationReceipt, QAfterFilterCondition>
  idGreaterThan(Id value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'id',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<MutationReceipt, MutationReceipt, QAfterFilterCondition>
  idLessThan(Id value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'id',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<MutationReceipt, MutationReceipt, QAfterFilterCondition>
  idBetween(
    Id lower,
    Id upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'id',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
        ),
      );
    });
  }

  QueryBuilder<MutationReceipt, MutationReceipt, QAfterFilterCondition>
  methodEqualTo(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'method',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<MutationReceipt, MutationReceipt, QAfterFilterCondition>
  methodGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'method',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<MutationReceipt, MutationReceipt, QAfterFilterCondition>
  methodLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'method',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<MutationReceipt, MutationReceipt, QAfterFilterCondition>
  methodBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'method',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<MutationReceipt, MutationReceipt, QAfterFilterCondition>
  methodStartsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.startsWith(
          property: r'method',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<MutationReceipt, MutationReceipt, QAfterFilterCondition>
  methodEndsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.endsWith(
          property: r'method',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<MutationReceipt, MutationReceipt, QAfterFilterCondition>
  methodContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.contains(
          property: r'method',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<MutationReceipt, MutationReceipt, QAfterFilterCondition>
  methodMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.matches(
          property: r'method',
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<MutationReceipt, MutationReceipt, QAfterFilterCondition>
  methodIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'method', value: ''),
      );
    });
  }

  QueryBuilder<MutationReceipt, MutationReceipt, QAfterFilterCondition>
  methodIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(property: r'method', value: ''),
      );
    });
  }

  QueryBuilder<MutationReceipt, MutationReceipt, QAfterFilterCondition>
  mutationIdEqualTo(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'mutationId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<MutationReceipt, MutationReceipt, QAfterFilterCondition>
  mutationIdGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'mutationId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<MutationReceipt, MutationReceipt, QAfterFilterCondition>
  mutationIdLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'mutationId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<MutationReceipt, MutationReceipt, QAfterFilterCondition>
  mutationIdBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'mutationId',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<MutationReceipt, MutationReceipt, QAfterFilterCondition>
  mutationIdStartsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.startsWith(
          property: r'mutationId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<MutationReceipt, MutationReceipt, QAfterFilterCondition>
  mutationIdEndsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.endsWith(
          property: r'mutationId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<MutationReceipt, MutationReceipt, QAfterFilterCondition>
  mutationIdContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.contains(
          property: r'mutationId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<MutationReceipt, MutationReceipt, QAfterFilterCondition>
  mutationIdMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.matches(
          property: r'mutationId',
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<MutationReceipt, MutationReceipt, QAfterFilterCondition>
  mutationIdIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'mutationId', value: ''),
      );
    });
  }

  QueryBuilder<MutationReceipt, MutationReceipt, QAfterFilterCondition>
  mutationIdIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(property: r'mutationId', value: ''),
      );
    });
  }

  QueryBuilder<MutationReceipt, MutationReceipt, QAfterFilterCondition>
  payloadHmacElementEqualTo(int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'payloadHmac', value: value),
      );
    });
  }

  QueryBuilder<MutationReceipt, MutationReceipt, QAfterFilterCondition>
  payloadHmacElementGreaterThan(int value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'payloadHmac',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<MutationReceipt, MutationReceipt, QAfterFilterCondition>
  payloadHmacElementLessThan(int value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'payloadHmac',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<MutationReceipt, MutationReceipt, QAfterFilterCondition>
  payloadHmacElementBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'payloadHmac',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
        ),
      );
    });
  }

  QueryBuilder<MutationReceipt, MutationReceipt, QAfterFilterCondition>
  payloadHmacLengthEqualTo(int length) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(r'payloadHmac', length, true, length, true);
    });
  }

  QueryBuilder<MutationReceipt, MutationReceipt, QAfterFilterCondition>
  payloadHmacIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(r'payloadHmac', 0, true, 0, true);
    });
  }

  QueryBuilder<MutationReceipt, MutationReceipt, QAfterFilterCondition>
  payloadHmacIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(r'payloadHmac', 0, false, 999999, true);
    });
  }

  QueryBuilder<MutationReceipt, MutationReceipt, QAfterFilterCondition>
  payloadHmacLengthLessThan(int length, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(r'payloadHmac', 0, true, length, include);
    });
  }

  QueryBuilder<MutationReceipt, MutationReceipt, QAfterFilterCondition>
  payloadHmacLengthGreaterThan(int length, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(r'payloadHmac', length, include, 999999, true);
    });
  }

  QueryBuilder<MutationReceipt, MutationReceipt, QAfterFilterCondition>
  payloadHmacLengthBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'payloadHmac',
        lower,
        includeLower,
        upper,
        includeUpper,
      );
    });
  }

  QueryBuilder<MutationReceipt, MutationReceipt, QAfterFilterCondition>
  resultCodeEqualTo(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'resultCode',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<MutationReceipt, MutationReceipt, QAfterFilterCondition>
  resultCodeGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'resultCode',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<MutationReceipt, MutationReceipt, QAfterFilterCondition>
  resultCodeLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'resultCode',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<MutationReceipt, MutationReceipt, QAfterFilterCondition>
  resultCodeBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'resultCode',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<MutationReceipt, MutationReceipt, QAfterFilterCondition>
  resultCodeStartsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.startsWith(
          property: r'resultCode',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<MutationReceipt, MutationReceipt, QAfterFilterCondition>
  resultCodeEndsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.endsWith(
          property: r'resultCode',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<MutationReceipt, MutationReceipt, QAfterFilterCondition>
  resultCodeContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.contains(
          property: r'resultCode',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<MutationReceipt, MutationReceipt, QAfterFilterCondition>
  resultCodeMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.matches(
          property: r'resultCode',
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<MutationReceipt, MutationReceipt, QAfterFilterCondition>
  resultCodeIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'resultCode', value: ''),
      );
    });
  }

  QueryBuilder<MutationReceipt, MutationReceipt, QAfterFilterCondition>
  resultCodeIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(property: r'resultCode', value: ''),
      );
    });
  }
}

extension MutationReceiptQueryObject
    on QueryBuilder<MutationReceipt, MutationReceipt, QFilterCondition> {}

extension MutationReceiptQueryLinks
    on QueryBuilder<MutationReceipt, MutationReceipt, QFilterCondition> {}

extension MutationReceiptQuerySortBy
    on QueryBuilder<MutationReceipt, MutationReceipt, QSortBy> {
  QueryBuilder<MutationReceipt, MutationReceipt, QAfterSortBy>
  sortByClientId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'clientId', Sort.asc);
    });
  }

  QueryBuilder<MutationReceipt, MutationReceipt, QAfterSortBy>
  sortByClientIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'clientId', Sort.desc);
    });
  }

  QueryBuilder<MutationReceipt, MutationReceipt, QAfterSortBy>
  sortByCommittedDataRevision() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'committedDataRevision', Sort.asc);
    });
  }

  QueryBuilder<MutationReceipt, MutationReceipt, QAfterSortBy>
  sortByCommittedDataRevisionDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'committedDataRevision', Sort.desc);
    });
  }

  QueryBuilder<MutationReceipt, MutationReceipt, QAfterSortBy>
  sortByCreatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'createdAt', Sort.asc);
    });
  }

  QueryBuilder<MutationReceipt, MutationReceipt, QAfterSortBy>
  sortByCreatedAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'createdAt', Sort.desc);
    });
  }

  QueryBuilder<MutationReceipt, MutationReceipt, QAfterSortBy>
  sortByExpiresAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'expiresAt', Sort.asc);
    });
  }

  QueryBuilder<MutationReceipt, MutationReceipt, QAfterSortBy>
  sortByExpiresAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'expiresAt', Sort.desc);
    });
  }

  QueryBuilder<MutationReceipt, MutationReceipt, QAfterSortBy> sortByMethod() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'method', Sort.asc);
    });
  }

  QueryBuilder<MutationReceipt, MutationReceipt, QAfterSortBy>
  sortByMethodDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'method', Sort.desc);
    });
  }

  QueryBuilder<MutationReceipt, MutationReceipt, QAfterSortBy>
  sortByMutationId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'mutationId', Sort.asc);
    });
  }

  QueryBuilder<MutationReceipt, MutationReceipt, QAfterSortBy>
  sortByMutationIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'mutationId', Sort.desc);
    });
  }

  QueryBuilder<MutationReceipt, MutationReceipt, QAfterSortBy>
  sortByResultCode() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'resultCode', Sort.asc);
    });
  }

  QueryBuilder<MutationReceipt, MutationReceipt, QAfterSortBy>
  sortByResultCodeDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'resultCode', Sort.desc);
    });
  }
}

extension MutationReceiptQuerySortThenBy
    on QueryBuilder<MutationReceipt, MutationReceipt, QSortThenBy> {
  QueryBuilder<MutationReceipt, MutationReceipt, QAfterSortBy>
  thenByClientId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'clientId', Sort.asc);
    });
  }

  QueryBuilder<MutationReceipt, MutationReceipt, QAfterSortBy>
  thenByClientIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'clientId', Sort.desc);
    });
  }

  QueryBuilder<MutationReceipt, MutationReceipt, QAfterSortBy>
  thenByCommittedDataRevision() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'committedDataRevision', Sort.asc);
    });
  }

  QueryBuilder<MutationReceipt, MutationReceipt, QAfterSortBy>
  thenByCommittedDataRevisionDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'committedDataRevision', Sort.desc);
    });
  }

  QueryBuilder<MutationReceipt, MutationReceipt, QAfterSortBy>
  thenByCreatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'createdAt', Sort.asc);
    });
  }

  QueryBuilder<MutationReceipt, MutationReceipt, QAfterSortBy>
  thenByCreatedAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'createdAt', Sort.desc);
    });
  }

  QueryBuilder<MutationReceipt, MutationReceipt, QAfterSortBy>
  thenByExpiresAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'expiresAt', Sort.asc);
    });
  }

  QueryBuilder<MutationReceipt, MutationReceipt, QAfterSortBy>
  thenByExpiresAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'expiresAt', Sort.desc);
    });
  }

  QueryBuilder<MutationReceipt, MutationReceipt, QAfterSortBy> thenById() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.asc);
    });
  }

  QueryBuilder<MutationReceipt, MutationReceipt, QAfterSortBy> thenByIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.desc);
    });
  }

  QueryBuilder<MutationReceipt, MutationReceipt, QAfterSortBy> thenByMethod() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'method', Sort.asc);
    });
  }

  QueryBuilder<MutationReceipt, MutationReceipt, QAfterSortBy>
  thenByMethodDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'method', Sort.desc);
    });
  }

  QueryBuilder<MutationReceipt, MutationReceipt, QAfterSortBy>
  thenByMutationId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'mutationId', Sort.asc);
    });
  }

  QueryBuilder<MutationReceipt, MutationReceipt, QAfterSortBy>
  thenByMutationIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'mutationId', Sort.desc);
    });
  }

  QueryBuilder<MutationReceipt, MutationReceipt, QAfterSortBy>
  thenByResultCode() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'resultCode', Sort.asc);
    });
  }

  QueryBuilder<MutationReceipt, MutationReceipt, QAfterSortBy>
  thenByResultCodeDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'resultCode', Sort.desc);
    });
  }
}

extension MutationReceiptQueryWhereDistinct
    on QueryBuilder<MutationReceipt, MutationReceipt, QDistinct> {
  QueryBuilder<MutationReceipt, MutationReceipt, QDistinct> distinctByClientId({
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'clientId', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<MutationReceipt, MutationReceipt, QDistinct>
  distinctByCommittedDataRevision() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'committedDataRevision');
    });
  }

  QueryBuilder<MutationReceipt, MutationReceipt, QDistinct>
  distinctByCreatedAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'createdAt');
    });
  }

  QueryBuilder<MutationReceipt, MutationReceipt, QDistinct>
  distinctByEntityIds() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'entityIds');
    });
  }

  QueryBuilder<MutationReceipt, MutationReceipt, QDistinct>
  distinctByEntityRevisions() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'entityRevisions');
    });
  }

  QueryBuilder<MutationReceipt, MutationReceipt, QDistinct>
  distinctByExpiresAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'expiresAt');
    });
  }

  QueryBuilder<MutationReceipt, MutationReceipt, QDistinct> distinctByMethod({
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'method', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<MutationReceipt, MutationReceipt, QDistinct>
  distinctByMutationId({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'mutationId', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<MutationReceipt, MutationReceipt, QDistinct>
  distinctByPayloadHmac() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'payloadHmac');
    });
  }

  QueryBuilder<MutationReceipt, MutationReceipt, QDistinct>
  distinctByResultCode({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'resultCode', caseSensitive: caseSensitive);
    });
  }
}

extension MutationReceiptQueryProperty
    on QueryBuilder<MutationReceipt, MutationReceipt, QQueryProperty> {
  QueryBuilder<MutationReceipt, int, QQueryOperations> idProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'id');
    });
  }

  QueryBuilder<MutationReceipt, String, QQueryOperations> clientIdProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'clientId');
    });
  }

  QueryBuilder<MutationReceipt, int, QQueryOperations>
  committedDataRevisionProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'committedDataRevision');
    });
  }

  QueryBuilder<MutationReceipt, int, QQueryOperations> createdAtProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'createdAt');
    });
  }

  QueryBuilder<MutationReceipt, List<String>, QQueryOperations>
  entityIdsProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'entityIds');
    });
  }

  QueryBuilder<MutationReceipt, List<int>, QQueryOperations>
  entityRevisionsProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'entityRevisions');
    });
  }

  QueryBuilder<MutationReceipt, int, QQueryOperations> expiresAtProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'expiresAt');
    });
  }

  QueryBuilder<MutationReceipt, String, QQueryOperations> methodProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'method');
    });
  }

  QueryBuilder<MutationReceipt, String, QQueryOperations> mutationIdProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'mutationId');
    });
  }

  QueryBuilder<MutationReceipt, List<int>, QQueryOperations>
  payloadHmacProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'payloadHmac');
    });
  }

  QueryBuilder<MutationReceipt, String, QQueryOperations> resultCodeProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'resultCode');
    });
  }
}

// coverage:ignore-file
// ignore_for_file: duplicate_ignore, non_constant_identifier_names, constant_identifier_names, invalid_use_of_protected_member, unnecessary_cast, prefer_const_constructors, lines_longer_than_80_chars, require_trailing_commas, inference_failure_on_function_invocation, unnecessary_parenthesis, unnecessary_raw_strings, unnecessary_null_checks, join_return_with_assignment, prefer_final_locals, avoid_js_rounded_ints, avoid_positional_boolean_parameters, always_specify_types, experimental_member_use

extension GetSecurityStateCollection on Isar {
  IsarCollection<SecurityState> get securityStates => this.collection();
}

const SecurityStateSchema = CollectionSchema(
  name: r'SecurityState',
  id: -6009074615644932597,
  properties: {
    r'authorizationEpoch': PropertySchema(
      id: 0,
      name: r'authorizationEpoch',
      type: IsarType.long,
    ),
    r'lastAuthorizationUtc': PropertySchema(
      id: 1,
      name: r'lastAuthorizationUtc',
      type: IsarType.long,
    ),
    r'lastClockRollbackAt': PropertySchema(
      id: 2,
      name: r'lastClockRollbackAt',
      type: IsarType.long,
    ),
    r'minimumClockUtc': PropertySchema(
      id: 3,
      name: r'minimumClockUtc',
      type: IsarType.long,
    ),
    r'protectedReceiptHmacKey': PropertySchema(
      id: 4,
      name: r'protectedReceiptHmacKey',
      type: IsarType.byteList,
    ),
  },

  estimateSize: _securityStateEstimateSize,
  serialize: _securityStateSerialize,
  deserialize: _securityStateDeserialize,
  deserializeProp: _securityStateDeserializeProp,
  idName: r'id',
  indexes: {},
  links: {},
  embeddedSchemas: {},

  getId: _securityStateGetId,
  getLinks: _securityStateGetLinks,
  attach: _securityStateAttach,
  version: '3.4.1',
);

int _securityStateEstimateSize(
  SecurityState object,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  var bytesCount = offsets.last;
  bytesCount += 3 + object.protectedReceiptHmacKey.length;
  return bytesCount;
}

void _securityStateSerialize(
  SecurityState object,
  IsarWriter writer,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  writer.writeLong(offsets[0], object.authorizationEpoch);
  writer.writeLong(offsets[1], object.lastAuthorizationUtc);
  writer.writeLong(offsets[2], object.lastClockRollbackAt);
  writer.writeLong(offsets[3], object.minimumClockUtc);
  writer.writeByteList(offsets[4], object.protectedReceiptHmacKey);
}

SecurityState _securityStateDeserialize(
  Id id,
  IsarReader reader,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  final object = SecurityState();
  object.authorizationEpoch = reader.readLong(offsets[0]);
  object.id = id;
  object.lastAuthorizationUtc = reader.readLong(offsets[1]);
  object.lastClockRollbackAt = reader.readLongOrNull(offsets[2]);
  object.minimumClockUtc = reader.readLong(offsets[3]);
  object.protectedReceiptHmacKey = reader.readByteList(offsets[4]) ?? [];
  return object;
}

P _securityStateDeserializeProp<P>(
  IsarReader reader,
  int propertyId,
  int offset,
  Map<Type, List<int>> allOffsets,
) {
  switch (propertyId) {
    case 0:
      return (reader.readLong(offset)) as P;
    case 1:
      return (reader.readLong(offset)) as P;
    case 2:
      return (reader.readLongOrNull(offset)) as P;
    case 3:
      return (reader.readLong(offset)) as P;
    case 4:
      return (reader.readByteList(offset) ?? []) as P;
    default:
      throw IsarError('Unknown property with id $propertyId');
  }
}

Id _securityStateGetId(SecurityState object) {
  return object.id;
}

List<IsarLinkBase<dynamic>> _securityStateGetLinks(SecurityState object) {
  return [];
}

void _securityStateAttach(
  IsarCollection<dynamic> col,
  Id id,
  SecurityState object,
) {
  object.id = id;
}

extension SecurityStateQueryWhereSort
    on QueryBuilder<SecurityState, SecurityState, QWhere> {
  QueryBuilder<SecurityState, SecurityState, QAfterWhere> anyId() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(const IdWhereClause.any());
    });
  }
}

extension SecurityStateQueryWhere
    on QueryBuilder<SecurityState, SecurityState, QWhereClause> {
  QueryBuilder<SecurityState, SecurityState, QAfterWhereClause> idEqualTo(
    Id id,
  ) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IdWhereClause.between(lower: id, upper: id));
    });
  }

  QueryBuilder<SecurityState, SecurityState, QAfterWhereClause> idNotEqualTo(
    Id id,
  ) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(
              IdWhereClause.lessThan(upper: id, includeUpper: false),
            )
            .addWhereClause(
              IdWhereClause.greaterThan(lower: id, includeLower: false),
            );
      } else {
        return query
            .addWhereClause(
              IdWhereClause.greaterThan(lower: id, includeLower: false),
            )
            .addWhereClause(
              IdWhereClause.lessThan(upper: id, includeUpper: false),
            );
      }
    });
  }

  QueryBuilder<SecurityState, SecurityState, QAfterWhereClause> idGreaterThan(
    Id id, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.greaterThan(lower: id, includeLower: include),
      );
    });
  }

  QueryBuilder<SecurityState, SecurityState, QAfterWhereClause> idLessThan(
    Id id, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.lessThan(upper: id, includeUpper: include),
      );
    });
  }

  QueryBuilder<SecurityState, SecurityState, QAfterWhereClause> idBetween(
    Id lowerId,
    Id upperId, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.between(
          lower: lowerId,
          includeLower: includeLower,
          upper: upperId,
          includeUpper: includeUpper,
        ),
      );
    });
  }
}

extension SecurityStateQueryFilter
    on QueryBuilder<SecurityState, SecurityState, QFilterCondition> {
  QueryBuilder<SecurityState, SecurityState, QAfterFilterCondition>
  authorizationEpochEqualTo(int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'authorizationEpoch', value: value),
      );
    });
  }

  QueryBuilder<SecurityState, SecurityState, QAfterFilterCondition>
  authorizationEpochGreaterThan(int value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'authorizationEpoch',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<SecurityState, SecurityState, QAfterFilterCondition>
  authorizationEpochLessThan(int value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'authorizationEpoch',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<SecurityState, SecurityState, QAfterFilterCondition>
  authorizationEpochBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'authorizationEpoch',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
        ),
      );
    });
  }

  QueryBuilder<SecurityState, SecurityState, QAfterFilterCondition> idEqualTo(
    Id value,
  ) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'id', value: value),
      );
    });
  }

  QueryBuilder<SecurityState, SecurityState, QAfterFilterCondition>
  idGreaterThan(Id value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'id',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<SecurityState, SecurityState, QAfterFilterCondition> idLessThan(
    Id value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'id',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<SecurityState, SecurityState, QAfterFilterCondition> idBetween(
    Id lower,
    Id upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'id',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
        ),
      );
    });
  }

  QueryBuilder<SecurityState, SecurityState, QAfterFilterCondition>
  lastAuthorizationUtcEqualTo(int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'lastAuthorizationUtc',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<SecurityState, SecurityState, QAfterFilterCondition>
  lastAuthorizationUtcGreaterThan(int value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'lastAuthorizationUtc',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<SecurityState, SecurityState, QAfterFilterCondition>
  lastAuthorizationUtcLessThan(int value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'lastAuthorizationUtc',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<SecurityState, SecurityState, QAfterFilterCondition>
  lastAuthorizationUtcBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'lastAuthorizationUtc',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
        ),
      );
    });
  }

  QueryBuilder<SecurityState, SecurityState, QAfterFilterCondition>
  lastClockRollbackAtIsNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNull(property: r'lastClockRollbackAt'),
      );
    });
  }

  QueryBuilder<SecurityState, SecurityState, QAfterFilterCondition>
  lastClockRollbackAtIsNotNull() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        const FilterCondition.isNotNull(property: r'lastClockRollbackAt'),
      );
    });
  }

  QueryBuilder<SecurityState, SecurityState, QAfterFilterCondition>
  lastClockRollbackAtEqualTo(int? value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'lastClockRollbackAt', value: value),
      );
    });
  }

  QueryBuilder<SecurityState, SecurityState, QAfterFilterCondition>
  lastClockRollbackAtGreaterThan(int? value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'lastClockRollbackAt',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<SecurityState, SecurityState, QAfterFilterCondition>
  lastClockRollbackAtLessThan(int? value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'lastClockRollbackAt',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<SecurityState, SecurityState, QAfterFilterCondition>
  lastClockRollbackAtBetween(
    int? lower,
    int? upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'lastClockRollbackAt',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
        ),
      );
    });
  }

  QueryBuilder<SecurityState, SecurityState, QAfterFilterCondition>
  minimumClockUtcEqualTo(int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'minimumClockUtc', value: value),
      );
    });
  }

  QueryBuilder<SecurityState, SecurityState, QAfterFilterCondition>
  minimumClockUtcGreaterThan(int value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'minimumClockUtc',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<SecurityState, SecurityState, QAfterFilterCondition>
  minimumClockUtcLessThan(int value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'minimumClockUtc',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<SecurityState, SecurityState, QAfterFilterCondition>
  minimumClockUtcBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'minimumClockUtc',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
        ),
      );
    });
  }

  QueryBuilder<SecurityState, SecurityState, QAfterFilterCondition>
  protectedReceiptHmacKeyElementEqualTo(int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'protectedReceiptHmacKey',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<SecurityState, SecurityState, QAfterFilterCondition>
  protectedReceiptHmacKeyElementGreaterThan(int value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'protectedReceiptHmacKey',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<SecurityState, SecurityState, QAfterFilterCondition>
  protectedReceiptHmacKeyElementLessThan(int value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'protectedReceiptHmacKey',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<SecurityState, SecurityState, QAfterFilterCondition>
  protectedReceiptHmacKeyElementBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'protectedReceiptHmacKey',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
        ),
      );
    });
  }

  QueryBuilder<SecurityState, SecurityState, QAfterFilterCondition>
  protectedReceiptHmacKeyLengthEqualTo(int length) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'protectedReceiptHmacKey',
        length,
        true,
        length,
        true,
      );
    });
  }

  QueryBuilder<SecurityState, SecurityState, QAfterFilterCondition>
  protectedReceiptHmacKeyIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(r'protectedReceiptHmacKey', 0, true, 0, true);
    });
  }

  QueryBuilder<SecurityState, SecurityState, QAfterFilterCondition>
  protectedReceiptHmacKeyIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'protectedReceiptHmacKey',
        0,
        false,
        999999,
        true,
      );
    });
  }

  QueryBuilder<SecurityState, SecurityState, QAfterFilterCondition>
  protectedReceiptHmacKeyLengthLessThan(int length, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'protectedReceiptHmacKey',
        0,
        true,
        length,
        include,
      );
    });
  }

  QueryBuilder<SecurityState, SecurityState, QAfterFilterCondition>
  protectedReceiptHmacKeyLengthGreaterThan(int length, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'protectedReceiptHmacKey',
        length,
        include,
        999999,
        true,
      );
    });
  }

  QueryBuilder<SecurityState, SecurityState, QAfterFilterCondition>
  protectedReceiptHmacKeyLengthBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.listLength(
        r'protectedReceiptHmacKey',
        lower,
        includeLower,
        upper,
        includeUpper,
      );
    });
  }
}

extension SecurityStateQueryObject
    on QueryBuilder<SecurityState, SecurityState, QFilterCondition> {}

extension SecurityStateQueryLinks
    on QueryBuilder<SecurityState, SecurityState, QFilterCondition> {}

extension SecurityStateQuerySortBy
    on QueryBuilder<SecurityState, SecurityState, QSortBy> {
  QueryBuilder<SecurityState, SecurityState, QAfterSortBy>
  sortByAuthorizationEpoch() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'authorizationEpoch', Sort.asc);
    });
  }

  QueryBuilder<SecurityState, SecurityState, QAfterSortBy>
  sortByAuthorizationEpochDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'authorizationEpoch', Sort.desc);
    });
  }

  QueryBuilder<SecurityState, SecurityState, QAfterSortBy>
  sortByLastAuthorizationUtc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lastAuthorizationUtc', Sort.asc);
    });
  }

  QueryBuilder<SecurityState, SecurityState, QAfterSortBy>
  sortByLastAuthorizationUtcDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lastAuthorizationUtc', Sort.desc);
    });
  }

  QueryBuilder<SecurityState, SecurityState, QAfterSortBy>
  sortByLastClockRollbackAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lastClockRollbackAt', Sort.asc);
    });
  }

  QueryBuilder<SecurityState, SecurityState, QAfterSortBy>
  sortByLastClockRollbackAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lastClockRollbackAt', Sort.desc);
    });
  }

  QueryBuilder<SecurityState, SecurityState, QAfterSortBy>
  sortByMinimumClockUtc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'minimumClockUtc', Sort.asc);
    });
  }

  QueryBuilder<SecurityState, SecurityState, QAfterSortBy>
  sortByMinimumClockUtcDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'minimumClockUtc', Sort.desc);
    });
  }
}

extension SecurityStateQuerySortThenBy
    on QueryBuilder<SecurityState, SecurityState, QSortThenBy> {
  QueryBuilder<SecurityState, SecurityState, QAfterSortBy>
  thenByAuthorizationEpoch() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'authorizationEpoch', Sort.asc);
    });
  }

  QueryBuilder<SecurityState, SecurityState, QAfterSortBy>
  thenByAuthorizationEpochDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'authorizationEpoch', Sort.desc);
    });
  }

  QueryBuilder<SecurityState, SecurityState, QAfterSortBy> thenById() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.asc);
    });
  }

  QueryBuilder<SecurityState, SecurityState, QAfterSortBy> thenByIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.desc);
    });
  }

  QueryBuilder<SecurityState, SecurityState, QAfterSortBy>
  thenByLastAuthorizationUtc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lastAuthorizationUtc', Sort.asc);
    });
  }

  QueryBuilder<SecurityState, SecurityState, QAfterSortBy>
  thenByLastAuthorizationUtcDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lastAuthorizationUtc', Sort.desc);
    });
  }

  QueryBuilder<SecurityState, SecurityState, QAfterSortBy>
  thenByLastClockRollbackAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lastClockRollbackAt', Sort.asc);
    });
  }

  QueryBuilder<SecurityState, SecurityState, QAfterSortBy>
  thenByLastClockRollbackAtDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'lastClockRollbackAt', Sort.desc);
    });
  }

  QueryBuilder<SecurityState, SecurityState, QAfterSortBy>
  thenByMinimumClockUtc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'minimumClockUtc', Sort.asc);
    });
  }

  QueryBuilder<SecurityState, SecurityState, QAfterSortBy>
  thenByMinimumClockUtcDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'minimumClockUtc', Sort.desc);
    });
  }
}

extension SecurityStateQueryWhereDistinct
    on QueryBuilder<SecurityState, SecurityState, QDistinct> {
  QueryBuilder<SecurityState, SecurityState, QDistinct>
  distinctByAuthorizationEpoch() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'authorizationEpoch');
    });
  }

  QueryBuilder<SecurityState, SecurityState, QDistinct>
  distinctByLastAuthorizationUtc() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'lastAuthorizationUtc');
    });
  }

  QueryBuilder<SecurityState, SecurityState, QDistinct>
  distinctByLastClockRollbackAt() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'lastClockRollbackAt');
    });
  }

  QueryBuilder<SecurityState, SecurityState, QDistinct>
  distinctByMinimumClockUtc() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'minimumClockUtc');
    });
  }

  QueryBuilder<SecurityState, SecurityState, QDistinct>
  distinctByProtectedReceiptHmacKey() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'protectedReceiptHmacKey');
    });
  }
}

extension SecurityStateQueryProperty
    on QueryBuilder<SecurityState, SecurityState, QQueryProperty> {
  QueryBuilder<SecurityState, int, QQueryOperations> idProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'id');
    });
  }

  QueryBuilder<SecurityState, int, QQueryOperations>
  authorizationEpochProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'authorizationEpoch');
    });
  }

  QueryBuilder<SecurityState, int, QQueryOperations>
  lastAuthorizationUtcProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'lastAuthorizationUtc');
    });
  }

  QueryBuilder<SecurityState, int?, QQueryOperations>
  lastClockRollbackAtProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'lastClockRollbackAt');
    });
  }

  QueryBuilder<SecurityState, int, QQueryOperations> minimumClockUtcProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'minimumClockUtc');
    });
  }

  QueryBuilder<SecurityState, List<int>, QQueryOperations>
  protectedReceiptHmacKeyProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'protectedReceiptHmacKey');
    });
  }
}

// coverage:ignore-file
// ignore_for_file: duplicate_ignore, non_constant_identifier_names, constant_identifier_names, invalid_use_of_protected_member, unnecessary_cast, prefer_const_constructors, lines_longer_than_80_chars, require_trailing_commas, inference_failure_on_function_invocation, unnecessary_parenthesis, unnecessary_raw_strings, unnecessary_null_checks, join_return_with_assignment, prefer_final_locals, avoid_js_rounded_ints, avoid_positional_boolean_parameters, always_specify_types, experimental_member_use

extension GetMonitoringHistoryRecordCollection on Isar {
  IsarCollection<MonitoringHistoryRecord> get monitoringHistoryRecords =>
      this.collection();
}

const MonitoringHistoryRecordSchema = CollectionSchema(
  name: r'MonitoringHistoryRecord',
  id: 893806302993831305,
  properties: {
    r'connectionRevision': PropertySchema(
      id: 0,
      name: r'connectionRevision',
      type: IsarType.long,
    ),
    r'payload': PropertySchema(id: 1, name: r'payload', type: IsarType.string),
    r'profileId': PropertySchema(
      id: 2,
      name: r'profileId',
      type: IsarType.string,
    ),
  },

  estimateSize: _monitoringHistoryRecordEstimateSize,
  serialize: _monitoringHistoryRecordSerialize,
  deserialize: _monitoringHistoryRecordDeserialize,
  deserializeProp: _monitoringHistoryRecordDeserializeProp,
  idName: r'id',
  indexes: {
    r'profileId': IndexSchema(
      id: 6052971939042612300,
      name: r'profileId',
      unique: true,
      replace: false,
      properties: [
        IndexPropertySchema(
          name: r'profileId',
          type: IndexType.hash,
          caseSensitive: true,
        ),
      ],
    ),
  },
  links: {},
  embeddedSchemas: {},

  getId: _monitoringHistoryRecordGetId,
  getLinks: _monitoringHistoryRecordGetLinks,
  attach: _monitoringHistoryRecordAttach,
  version: '3.4.1',
);

int _monitoringHistoryRecordEstimateSize(
  MonitoringHistoryRecord object,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  var bytesCount = offsets.last;
  bytesCount += 3 + object.payload.length * 3;
  bytesCount += 3 + object.profileId.length * 3;
  return bytesCount;
}

void _monitoringHistoryRecordSerialize(
  MonitoringHistoryRecord object,
  IsarWriter writer,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  writer.writeLong(offsets[0], object.connectionRevision);
  writer.writeString(offsets[1], object.payload);
  writer.writeString(offsets[2], object.profileId);
}

MonitoringHistoryRecord _monitoringHistoryRecordDeserialize(
  Id id,
  IsarReader reader,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  final object = MonitoringHistoryRecord();
  object.connectionRevision = reader.readLong(offsets[0]);
  object.id = id;
  object.payload = reader.readString(offsets[1]);
  object.profileId = reader.readString(offsets[2]);
  return object;
}

P _monitoringHistoryRecordDeserializeProp<P>(
  IsarReader reader,
  int propertyId,
  int offset,
  Map<Type, List<int>> allOffsets,
) {
  switch (propertyId) {
    case 0:
      return (reader.readLong(offset)) as P;
    case 1:
      return (reader.readString(offset)) as P;
    case 2:
      return (reader.readString(offset)) as P;
    default:
      throw IsarError('Unknown property with id $propertyId');
  }
}

Id _monitoringHistoryRecordGetId(MonitoringHistoryRecord object) {
  return object.id;
}

List<IsarLinkBase<dynamic>> _monitoringHistoryRecordGetLinks(
  MonitoringHistoryRecord object,
) {
  return [];
}

void _monitoringHistoryRecordAttach(
  IsarCollection<dynamic> col,
  Id id,
  MonitoringHistoryRecord object,
) {
  object.id = id;
}

extension MonitoringHistoryRecordByIndex
    on IsarCollection<MonitoringHistoryRecord> {
  Future<MonitoringHistoryRecord?> getByProfileId(String profileId) {
    return getByIndex(r'profileId', [profileId]);
  }

  MonitoringHistoryRecord? getByProfileIdSync(String profileId) {
    return getByIndexSync(r'profileId', [profileId]);
  }

  Future<bool> deleteByProfileId(String profileId) {
    return deleteByIndex(r'profileId', [profileId]);
  }

  bool deleteByProfileIdSync(String profileId) {
    return deleteByIndexSync(r'profileId', [profileId]);
  }

  Future<List<MonitoringHistoryRecord?>> getAllByProfileId(
    List<String> profileIdValues,
  ) {
    final values = profileIdValues.map((e) => [e]).toList();
    return getAllByIndex(r'profileId', values);
  }

  List<MonitoringHistoryRecord?> getAllByProfileIdSync(
    List<String> profileIdValues,
  ) {
    final values = profileIdValues.map((e) => [e]).toList();
    return getAllByIndexSync(r'profileId', values);
  }

  Future<int> deleteAllByProfileId(List<String> profileIdValues) {
    final values = profileIdValues.map((e) => [e]).toList();
    return deleteAllByIndex(r'profileId', values);
  }

  int deleteAllByProfileIdSync(List<String> profileIdValues) {
    final values = profileIdValues.map((e) => [e]).toList();
    return deleteAllByIndexSync(r'profileId', values);
  }

  Future<Id> putByProfileId(MonitoringHistoryRecord object) {
    return putByIndex(r'profileId', object);
  }

  Id putByProfileIdSync(
    MonitoringHistoryRecord object, {
    bool saveLinks = true,
  }) {
    return putByIndexSync(r'profileId', object, saveLinks: saveLinks);
  }

  Future<List<Id>> putAllByProfileId(List<MonitoringHistoryRecord> objects) {
    return putAllByIndex(r'profileId', objects);
  }

  List<Id> putAllByProfileIdSync(
    List<MonitoringHistoryRecord> objects, {
    bool saveLinks = true,
  }) {
    return putAllByIndexSync(r'profileId', objects, saveLinks: saveLinks);
  }
}

extension MonitoringHistoryRecordQueryWhereSort
    on QueryBuilder<MonitoringHistoryRecord, MonitoringHistoryRecord, QWhere> {
  QueryBuilder<MonitoringHistoryRecord, MonitoringHistoryRecord, QAfterWhere>
  anyId() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(const IdWhereClause.any());
    });
  }
}

extension MonitoringHistoryRecordQueryWhere
    on
        QueryBuilder<
          MonitoringHistoryRecord,
          MonitoringHistoryRecord,
          QWhereClause
        > {
  QueryBuilder<
    MonitoringHistoryRecord,
    MonitoringHistoryRecord,
    QAfterWhereClause
  >
  idEqualTo(Id id) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IdWhereClause.between(lower: id, upper: id));
    });
  }

  QueryBuilder<
    MonitoringHistoryRecord,
    MonitoringHistoryRecord,
    QAfterWhereClause
  >
  idNotEqualTo(Id id) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(
              IdWhereClause.lessThan(upper: id, includeUpper: false),
            )
            .addWhereClause(
              IdWhereClause.greaterThan(lower: id, includeLower: false),
            );
      } else {
        return query
            .addWhereClause(
              IdWhereClause.greaterThan(lower: id, includeLower: false),
            )
            .addWhereClause(
              IdWhereClause.lessThan(upper: id, includeUpper: false),
            );
      }
    });
  }

  QueryBuilder<
    MonitoringHistoryRecord,
    MonitoringHistoryRecord,
    QAfterWhereClause
  >
  idGreaterThan(Id id, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.greaterThan(lower: id, includeLower: include),
      );
    });
  }

  QueryBuilder<
    MonitoringHistoryRecord,
    MonitoringHistoryRecord,
    QAfterWhereClause
  >
  idLessThan(Id id, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.lessThan(upper: id, includeUpper: include),
      );
    });
  }

  QueryBuilder<
    MonitoringHistoryRecord,
    MonitoringHistoryRecord,
    QAfterWhereClause
  >
  idBetween(
    Id lowerId,
    Id upperId, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.between(
          lower: lowerId,
          includeLower: includeLower,
          upper: upperId,
          includeUpper: includeUpper,
        ),
      );
    });
  }

  QueryBuilder<
    MonitoringHistoryRecord,
    MonitoringHistoryRecord,
    QAfterWhereClause
  >
  profileIdEqualTo(String profileId) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IndexWhereClause.equalTo(indexName: r'profileId', value: [profileId]),
      );
    });
  }

  QueryBuilder<
    MonitoringHistoryRecord,
    MonitoringHistoryRecord,
    QAfterWhereClause
  >
  profileIdNotEqualTo(String profileId) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'profileId',
                lower: [],
                upper: [profileId],
                includeUpper: false,
              ),
            )
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'profileId',
                lower: [profileId],
                includeLower: false,
                upper: [],
              ),
            );
      } else {
        return query
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'profileId',
                lower: [profileId],
                includeLower: false,
                upper: [],
              ),
            )
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'profileId',
                lower: [],
                upper: [profileId],
                includeUpper: false,
              ),
            );
      }
    });
  }
}

extension MonitoringHistoryRecordQueryFilter
    on
        QueryBuilder<
          MonitoringHistoryRecord,
          MonitoringHistoryRecord,
          QFilterCondition
        > {
  QueryBuilder<
    MonitoringHistoryRecord,
    MonitoringHistoryRecord,
    QAfterFilterCondition
  >
  connectionRevisionEqualTo(int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'connectionRevision', value: value),
      );
    });
  }

  QueryBuilder<
    MonitoringHistoryRecord,
    MonitoringHistoryRecord,
    QAfterFilterCondition
  >
  connectionRevisionGreaterThan(int value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'connectionRevision',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<
    MonitoringHistoryRecord,
    MonitoringHistoryRecord,
    QAfterFilterCondition
  >
  connectionRevisionLessThan(int value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'connectionRevision',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<
    MonitoringHistoryRecord,
    MonitoringHistoryRecord,
    QAfterFilterCondition
  >
  connectionRevisionBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'connectionRevision',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
        ),
      );
    });
  }

  QueryBuilder<
    MonitoringHistoryRecord,
    MonitoringHistoryRecord,
    QAfterFilterCondition
  >
  idEqualTo(Id value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'id', value: value),
      );
    });
  }

  QueryBuilder<
    MonitoringHistoryRecord,
    MonitoringHistoryRecord,
    QAfterFilterCondition
  >
  idGreaterThan(Id value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'id',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<
    MonitoringHistoryRecord,
    MonitoringHistoryRecord,
    QAfterFilterCondition
  >
  idLessThan(Id value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'id',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<
    MonitoringHistoryRecord,
    MonitoringHistoryRecord,
    QAfterFilterCondition
  >
  idBetween(
    Id lower,
    Id upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'id',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
        ),
      );
    });
  }

  QueryBuilder<
    MonitoringHistoryRecord,
    MonitoringHistoryRecord,
    QAfterFilterCondition
  >
  payloadEqualTo(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'payload',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    MonitoringHistoryRecord,
    MonitoringHistoryRecord,
    QAfterFilterCondition
  >
  payloadGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'payload',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    MonitoringHistoryRecord,
    MonitoringHistoryRecord,
    QAfterFilterCondition
  >
  payloadLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'payload',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    MonitoringHistoryRecord,
    MonitoringHistoryRecord,
    QAfterFilterCondition
  >
  payloadBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'payload',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    MonitoringHistoryRecord,
    MonitoringHistoryRecord,
    QAfterFilterCondition
  >
  payloadStartsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.startsWith(
          property: r'payload',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    MonitoringHistoryRecord,
    MonitoringHistoryRecord,
    QAfterFilterCondition
  >
  payloadEndsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.endsWith(
          property: r'payload',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    MonitoringHistoryRecord,
    MonitoringHistoryRecord,
    QAfterFilterCondition
  >
  payloadContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.contains(
          property: r'payload',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    MonitoringHistoryRecord,
    MonitoringHistoryRecord,
    QAfterFilterCondition
  >
  payloadMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.matches(
          property: r'payload',
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    MonitoringHistoryRecord,
    MonitoringHistoryRecord,
    QAfterFilterCondition
  >
  payloadIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'payload', value: ''),
      );
    });
  }

  QueryBuilder<
    MonitoringHistoryRecord,
    MonitoringHistoryRecord,
    QAfterFilterCondition
  >
  payloadIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(property: r'payload', value: ''),
      );
    });
  }

  QueryBuilder<
    MonitoringHistoryRecord,
    MonitoringHistoryRecord,
    QAfterFilterCondition
  >
  profileIdEqualTo(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'profileId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    MonitoringHistoryRecord,
    MonitoringHistoryRecord,
    QAfterFilterCondition
  >
  profileIdGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'profileId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    MonitoringHistoryRecord,
    MonitoringHistoryRecord,
    QAfterFilterCondition
  >
  profileIdLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'profileId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    MonitoringHistoryRecord,
    MonitoringHistoryRecord,
    QAfterFilterCondition
  >
  profileIdBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'profileId',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    MonitoringHistoryRecord,
    MonitoringHistoryRecord,
    QAfterFilterCondition
  >
  profileIdStartsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.startsWith(
          property: r'profileId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    MonitoringHistoryRecord,
    MonitoringHistoryRecord,
    QAfterFilterCondition
  >
  profileIdEndsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.endsWith(
          property: r'profileId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    MonitoringHistoryRecord,
    MonitoringHistoryRecord,
    QAfterFilterCondition
  >
  profileIdContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.contains(
          property: r'profileId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    MonitoringHistoryRecord,
    MonitoringHistoryRecord,
    QAfterFilterCondition
  >
  profileIdMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.matches(
          property: r'profileId',
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<
    MonitoringHistoryRecord,
    MonitoringHistoryRecord,
    QAfterFilterCondition
  >
  profileIdIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'profileId', value: ''),
      );
    });
  }

  QueryBuilder<
    MonitoringHistoryRecord,
    MonitoringHistoryRecord,
    QAfterFilterCondition
  >
  profileIdIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(property: r'profileId', value: ''),
      );
    });
  }
}

extension MonitoringHistoryRecordQueryObject
    on
        QueryBuilder<
          MonitoringHistoryRecord,
          MonitoringHistoryRecord,
          QFilterCondition
        > {}

extension MonitoringHistoryRecordQueryLinks
    on
        QueryBuilder<
          MonitoringHistoryRecord,
          MonitoringHistoryRecord,
          QFilterCondition
        > {}

extension MonitoringHistoryRecordQuerySortBy
    on QueryBuilder<MonitoringHistoryRecord, MonitoringHistoryRecord, QSortBy> {
  QueryBuilder<MonitoringHistoryRecord, MonitoringHistoryRecord, QAfterSortBy>
  sortByConnectionRevision() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'connectionRevision', Sort.asc);
    });
  }

  QueryBuilder<MonitoringHistoryRecord, MonitoringHistoryRecord, QAfterSortBy>
  sortByConnectionRevisionDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'connectionRevision', Sort.desc);
    });
  }

  QueryBuilder<MonitoringHistoryRecord, MonitoringHistoryRecord, QAfterSortBy>
  sortByPayload() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'payload', Sort.asc);
    });
  }

  QueryBuilder<MonitoringHistoryRecord, MonitoringHistoryRecord, QAfterSortBy>
  sortByPayloadDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'payload', Sort.desc);
    });
  }

  QueryBuilder<MonitoringHistoryRecord, MonitoringHistoryRecord, QAfterSortBy>
  sortByProfileId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'profileId', Sort.asc);
    });
  }

  QueryBuilder<MonitoringHistoryRecord, MonitoringHistoryRecord, QAfterSortBy>
  sortByProfileIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'profileId', Sort.desc);
    });
  }
}

extension MonitoringHistoryRecordQuerySortThenBy
    on
        QueryBuilder<
          MonitoringHistoryRecord,
          MonitoringHistoryRecord,
          QSortThenBy
        > {
  QueryBuilder<MonitoringHistoryRecord, MonitoringHistoryRecord, QAfterSortBy>
  thenByConnectionRevision() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'connectionRevision', Sort.asc);
    });
  }

  QueryBuilder<MonitoringHistoryRecord, MonitoringHistoryRecord, QAfterSortBy>
  thenByConnectionRevisionDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'connectionRevision', Sort.desc);
    });
  }

  QueryBuilder<MonitoringHistoryRecord, MonitoringHistoryRecord, QAfterSortBy>
  thenById() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.asc);
    });
  }

  QueryBuilder<MonitoringHistoryRecord, MonitoringHistoryRecord, QAfterSortBy>
  thenByIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.desc);
    });
  }

  QueryBuilder<MonitoringHistoryRecord, MonitoringHistoryRecord, QAfterSortBy>
  thenByPayload() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'payload', Sort.asc);
    });
  }

  QueryBuilder<MonitoringHistoryRecord, MonitoringHistoryRecord, QAfterSortBy>
  thenByPayloadDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'payload', Sort.desc);
    });
  }

  QueryBuilder<MonitoringHistoryRecord, MonitoringHistoryRecord, QAfterSortBy>
  thenByProfileId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'profileId', Sort.asc);
    });
  }

  QueryBuilder<MonitoringHistoryRecord, MonitoringHistoryRecord, QAfterSortBy>
  thenByProfileIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'profileId', Sort.desc);
    });
  }
}

extension MonitoringHistoryRecordQueryWhereDistinct
    on
        QueryBuilder<
          MonitoringHistoryRecord,
          MonitoringHistoryRecord,
          QDistinct
        > {
  QueryBuilder<MonitoringHistoryRecord, MonitoringHistoryRecord, QDistinct>
  distinctByConnectionRevision() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'connectionRevision');
    });
  }

  QueryBuilder<MonitoringHistoryRecord, MonitoringHistoryRecord, QDistinct>
  distinctByPayload({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'payload', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<MonitoringHistoryRecord, MonitoringHistoryRecord, QDistinct>
  distinctByProfileId({bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'profileId', caseSensitive: caseSensitive);
    });
  }
}

extension MonitoringHistoryRecordQueryProperty
    on
        QueryBuilder<
          MonitoringHistoryRecord,
          MonitoringHistoryRecord,
          QQueryProperty
        > {
  QueryBuilder<MonitoringHistoryRecord, int, QQueryOperations> idProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'id');
    });
  }

  QueryBuilder<MonitoringHistoryRecord, int, QQueryOperations>
  connectionRevisionProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'connectionRevision');
    });
  }

  QueryBuilder<MonitoringHistoryRecord, String, QQueryOperations>
  payloadProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'payload');
    });
  }

  QueryBuilder<MonitoringHistoryRecord, String, QQueryOperations>
  profileIdProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'profileId');
    });
  }
}

// coverage:ignore-file
// ignore_for_file: duplicate_ignore, non_constant_identifier_names, constant_identifier_names, invalid_use_of_protected_member, unnecessary_cast, prefer_const_constructors, lines_longer_than_80_chars, require_trailing_commas, inference_failure_on_function_invocation, unnecessary_parenthesis, unnecessary_raw_strings, unnecessary_null_checks, join_return_with_assignment, prefer_final_locals, avoid_js_rounded_ints, avoid_positional_boolean_parameters, always_specify_types, experimental_member_use

extension GetJournalSourceCollection on Isar {
  IsarCollection<JournalSource> get journalSources => this.collection();
}

const JournalSourceSchema = CollectionSchema(
  name: r'JournalSource',
  id: -2261090565921168824,
  properties: {
    r'connectionRevision': PropertySchema(
      id: 0,
      name: r'connectionRevision',
      type: IsarType.long,
    ),
    r'enabled': PropertySchema(id: 1, name: r'enabled', type: IsarType.bool),
    r'kind': PropertySchema(id: 2, name: r'kind', type: IsarType.string),
    r'name': PropertySchema(id: 3, name: r'name', type: IsarType.string),
    r'payload': PropertySchema(id: 4, name: r'payload', type: IsarType.string),
    r'profileId': PropertySchema(
      id: 5,
      name: r'profileId',
      type: IsarType.string,
    ),
    r'sourceId': PropertySchema(
      id: 6,
      name: r'sourceId',
      type: IsarType.string,
    ),
    r'target': PropertySchema(id: 7, name: r'target', type: IsarType.string),
  },

  estimateSize: _journalSourceEstimateSize,
  serialize: _journalSourceSerialize,
  deserialize: _journalSourceDeserialize,
  deserializeProp: _journalSourceDeserializeProp,
  idName: r'id',
  indexes: {
    r'sourceId': IndexSchema(
      id: 2155220942429093580,
      name: r'sourceId',
      unique: true,
      replace: false,
      properties: [
        IndexPropertySchema(
          name: r'sourceId',
          type: IndexType.hash,
          caseSensitive: true,
        ),
      ],
    ),
    r'profileId': IndexSchema(
      id: 6052971939042612300,
      name: r'profileId',
      unique: false,
      replace: false,
      properties: [
        IndexPropertySchema(
          name: r'profileId',
          type: IndexType.hash,
          caseSensitive: true,
        ),
      ],
    ),
  },
  links: {},
  embeddedSchemas: {},

  getId: _journalSourceGetId,
  getLinks: _journalSourceGetLinks,
  attach: _journalSourceAttach,
  version: '3.4.1',
);

int _journalSourceEstimateSize(
  JournalSource object,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  var bytesCount = offsets.last;
  bytesCount += 3 + object.kind.length * 3;
  bytesCount += 3 + object.name.length * 3;
  bytesCount += 3 + object.payload.length * 3;
  bytesCount += 3 + object.profileId.length * 3;
  bytesCount += 3 + object.sourceId.length * 3;
  bytesCount += 3 + object.target.length * 3;
  return bytesCount;
}

void _journalSourceSerialize(
  JournalSource object,
  IsarWriter writer,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  writer.writeLong(offsets[0], object.connectionRevision);
  writer.writeBool(offsets[1], object.enabled);
  writer.writeString(offsets[2], object.kind);
  writer.writeString(offsets[3], object.name);
  writer.writeString(offsets[4], object.payload);
  writer.writeString(offsets[5], object.profileId);
  writer.writeString(offsets[6], object.sourceId);
  writer.writeString(offsets[7], object.target);
}

JournalSource _journalSourceDeserialize(
  Id id,
  IsarReader reader,
  List<int> offsets,
  Map<Type, List<int>> allOffsets,
) {
  final object = JournalSource();
  object.connectionRevision = reader.readLong(offsets[0]);
  object.enabled = reader.readBool(offsets[1]);
  object.id = id;
  object.kind = reader.readString(offsets[2]);
  object.name = reader.readString(offsets[3]);
  object.payload = reader.readString(offsets[4]);
  object.profileId = reader.readString(offsets[5]);
  object.sourceId = reader.readString(offsets[6]);
  object.target = reader.readString(offsets[7]);
  return object;
}

P _journalSourceDeserializeProp<P>(
  IsarReader reader,
  int propertyId,
  int offset,
  Map<Type, List<int>> allOffsets,
) {
  switch (propertyId) {
    case 0:
      return (reader.readLong(offset)) as P;
    case 1:
      return (reader.readBool(offset)) as P;
    case 2:
      return (reader.readString(offset)) as P;
    case 3:
      return (reader.readString(offset)) as P;
    case 4:
      return (reader.readString(offset)) as P;
    case 5:
      return (reader.readString(offset)) as P;
    case 6:
      return (reader.readString(offset)) as P;
    case 7:
      return (reader.readString(offset)) as P;
    default:
      throw IsarError('Unknown property with id $propertyId');
  }
}

Id _journalSourceGetId(JournalSource object) {
  return object.id;
}

List<IsarLinkBase<dynamic>> _journalSourceGetLinks(JournalSource object) {
  return [];
}

void _journalSourceAttach(
  IsarCollection<dynamic> col,
  Id id,
  JournalSource object,
) {
  object.id = id;
}

extension JournalSourceByIndex on IsarCollection<JournalSource> {
  Future<JournalSource?> getBySourceId(String sourceId) {
    return getByIndex(r'sourceId', [sourceId]);
  }

  JournalSource? getBySourceIdSync(String sourceId) {
    return getByIndexSync(r'sourceId', [sourceId]);
  }

  Future<bool> deleteBySourceId(String sourceId) {
    return deleteByIndex(r'sourceId', [sourceId]);
  }

  bool deleteBySourceIdSync(String sourceId) {
    return deleteByIndexSync(r'sourceId', [sourceId]);
  }

  Future<List<JournalSource?>> getAllBySourceId(List<String> sourceIdValues) {
    final values = sourceIdValues.map((e) => [e]).toList();
    return getAllByIndex(r'sourceId', values);
  }

  List<JournalSource?> getAllBySourceIdSync(List<String> sourceIdValues) {
    final values = sourceIdValues.map((e) => [e]).toList();
    return getAllByIndexSync(r'sourceId', values);
  }

  Future<int> deleteAllBySourceId(List<String> sourceIdValues) {
    final values = sourceIdValues.map((e) => [e]).toList();
    return deleteAllByIndex(r'sourceId', values);
  }

  int deleteAllBySourceIdSync(List<String> sourceIdValues) {
    final values = sourceIdValues.map((e) => [e]).toList();
    return deleteAllByIndexSync(r'sourceId', values);
  }

  Future<Id> putBySourceId(JournalSource object) {
    return putByIndex(r'sourceId', object);
  }

  Id putBySourceIdSync(JournalSource object, {bool saveLinks = true}) {
    return putByIndexSync(r'sourceId', object, saveLinks: saveLinks);
  }

  Future<List<Id>> putAllBySourceId(List<JournalSource> objects) {
    return putAllByIndex(r'sourceId', objects);
  }

  List<Id> putAllBySourceIdSync(
    List<JournalSource> objects, {
    bool saveLinks = true,
  }) {
    return putAllByIndexSync(r'sourceId', objects, saveLinks: saveLinks);
  }
}

extension JournalSourceQueryWhereSort
    on QueryBuilder<JournalSource, JournalSource, QWhere> {
  QueryBuilder<JournalSource, JournalSource, QAfterWhere> anyId() {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(const IdWhereClause.any());
    });
  }
}

extension JournalSourceQueryWhere
    on QueryBuilder<JournalSource, JournalSource, QWhereClause> {
  QueryBuilder<JournalSource, JournalSource, QAfterWhereClause> idEqualTo(
    Id id,
  ) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(IdWhereClause.between(lower: id, upper: id));
    });
  }

  QueryBuilder<JournalSource, JournalSource, QAfterWhereClause> idNotEqualTo(
    Id id,
  ) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(
              IdWhereClause.lessThan(upper: id, includeUpper: false),
            )
            .addWhereClause(
              IdWhereClause.greaterThan(lower: id, includeLower: false),
            );
      } else {
        return query
            .addWhereClause(
              IdWhereClause.greaterThan(lower: id, includeLower: false),
            )
            .addWhereClause(
              IdWhereClause.lessThan(upper: id, includeUpper: false),
            );
      }
    });
  }

  QueryBuilder<JournalSource, JournalSource, QAfterWhereClause> idGreaterThan(
    Id id, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.greaterThan(lower: id, includeLower: include),
      );
    });
  }

  QueryBuilder<JournalSource, JournalSource, QAfterWhereClause> idLessThan(
    Id id, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.lessThan(upper: id, includeUpper: include),
      );
    });
  }

  QueryBuilder<JournalSource, JournalSource, QAfterWhereClause> idBetween(
    Id lowerId,
    Id upperId, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IdWhereClause.between(
          lower: lowerId,
          includeLower: includeLower,
          upper: upperId,
          includeUpper: includeUpper,
        ),
      );
    });
  }

  QueryBuilder<JournalSource, JournalSource, QAfterWhereClause> sourceIdEqualTo(
    String sourceId,
  ) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IndexWhereClause.equalTo(indexName: r'sourceId', value: [sourceId]),
      );
    });
  }

  QueryBuilder<JournalSource, JournalSource, QAfterWhereClause>
  sourceIdNotEqualTo(String sourceId) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'sourceId',
                lower: [],
                upper: [sourceId],
                includeUpper: false,
              ),
            )
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'sourceId',
                lower: [sourceId],
                includeLower: false,
                upper: [],
              ),
            );
      } else {
        return query
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'sourceId',
                lower: [sourceId],
                includeLower: false,
                upper: [],
              ),
            )
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'sourceId',
                lower: [],
                upper: [sourceId],
                includeUpper: false,
              ),
            );
      }
    });
  }

  QueryBuilder<JournalSource, JournalSource, QAfterWhereClause>
  profileIdEqualTo(String profileId) {
    return QueryBuilder.apply(this, (query) {
      return query.addWhereClause(
        IndexWhereClause.equalTo(indexName: r'profileId', value: [profileId]),
      );
    });
  }

  QueryBuilder<JournalSource, JournalSource, QAfterWhereClause>
  profileIdNotEqualTo(String profileId) {
    return QueryBuilder.apply(this, (query) {
      if (query.whereSort == Sort.asc) {
        return query
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'profileId',
                lower: [],
                upper: [profileId],
                includeUpper: false,
              ),
            )
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'profileId',
                lower: [profileId],
                includeLower: false,
                upper: [],
              ),
            );
      } else {
        return query
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'profileId',
                lower: [profileId],
                includeLower: false,
                upper: [],
              ),
            )
            .addWhereClause(
              IndexWhereClause.between(
                indexName: r'profileId',
                lower: [],
                upper: [profileId],
                includeUpper: false,
              ),
            );
      }
    });
  }
}

extension JournalSourceQueryFilter
    on QueryBuilder<JournalSource, JournalSource, QFilterCondition> {
  QueryBuilder<JournalSource, JournalSource, QAfterFilterCondition>
  connectionRevisionEqualTo(int value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'connectionRevision', value: value),
      );
    });
  }

  QueryBuilder<JournalSource, JournalSource, QAfterFilterCondition>
  connectionRevisionGreaterThan(int value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'connectionRevision',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<JournalSource, JournalSource, QAfterFilterCondition>
  connectionRevisionLessThan(int value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'connectionRevision',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<JournalSource, JournalSource, QAfterFilterCondition>
  connectionRevisionBetween(
    int lower,
    int upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'connectionRevision',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
        ),
      );
    });
  }

  QueryBuilder<JournalSource, JournalSource, QAfterFilterCondition>
  enabledEqualTo(bool value) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'enabled', value: value),
      );
    });
  }

  QueryBuilder<JournalSource, JournalSource, QAfterFilterCondition> idEqualTo(
    Id value,
  ) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'id', value: value),
      );
    });
  }

  QueryBuilder<JournalSource, JournalSource, QAfterFilterCondition>
  idGreaterThan(Id value, {bool include = false}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'id',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<JournalSource, JournalSource, QAfterFilterCondition> idLessThan(
    Id value, {
    bool include = false,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'id',
          value: value,
        ),
      );
    });
  }

  QueryBuilder<JournalSource, JournalSource, QAfterFilterCondition> idBetween(
    Id lower,
    Id upper, {
    bool includeLower = true,
    bool includeUpper = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'id',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
        ),
      );
    });
  }

  QueryBuilder<JournalSource, JournalSource, QAfterFilterCondition> kindEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'kind',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<JournalSource, JournalSource, QAfterFilterCondition>
  kindGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'kind',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<JournalSource, JournalSource, QAfterFilterCondition>
  kindLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'kind',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<JournalSource, JournalSource, QAfterFilterCondition> kindBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'kind',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<JournalSource, JournalSource, QAfterFilterCondition>
  kindStartsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.startsWith(
          property: r'kind',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<JournalSource, JournalSource, QAfterFilterCondition>
  kindEndsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.endsWith(
          property: r'kind',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<JournalSource, JournalSource, QAfterFilterCondition>
  kindContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.contains(
          property: r'kind',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<JournalSource, JournalSource, QAfterFilterCondition> kindMatches(
    String pattern, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.matches(
          property: r'kind',
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<JournalSource, JournalSource, QAfterFilterCondition>
  kindIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'kind', value: ''),
      );
    });
  }

  QueryBuilder<JournalSource, JournalSource, QAfterFilterCondition>
  kindIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(property: r'kind', value: ''),
      );
    });
  }

  QueryBuilder<JournalSource, JournalSource, QAfterFilterCondition> nameEqualTo(
    String value, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'name',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<JournalSource, JournalSource, QAfterFilterCondition>
  nameGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'name',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<JournalSource, JournalSource, QAfterFilterCondition>
  nameLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'name',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<JournalSource, JournalSource, QAfterFilterCondition> nameBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'name',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<JournalSource, JournalSource, QAfterFilterCondition>
  nameStartsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.startsWith(
          property: r'name',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<JournalSource, JournalSource, QAfterFilterCondition>
  nameEndsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.endsWith(
          property: r'name',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<JournalSource, JournalSource, QAfterFilterCondition>
  nameContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.contains(
          property: r'name',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<JournalSource, JournalSource, QAfterFilterCondition> nameMatches(
    String pattern, {
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.matches(
          property: r'name',
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<JournalSource, JournalSource, QAfterFilterCondition>
  nameIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'name', value: ''),
      );
    });
  }

  QueryBuilder<JournalSource, JournalSource, QAfterFilterCondition>
  nameIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(property: r'name', value: ''),
      );
    });
  }

  QueryBuilder<JournalSource, JournalSource, QAfterFilterCondition>
  payloadEqualTo(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'payload',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<JournalSource, JournalSource, QAfterFilterCondition>
  payloadGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'payload',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<JournalSource, JournalSource, QAfterFilterCondition>
  payloadLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'payload',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<JournalSource, JournalSource, QAfterFilterCondition>
  payloadBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'payload',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<JournalSource, JournalSource, QAfterFilterCondition>
  payloadStartsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.startsWith(
          property: r'payload',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<JournalSource, JournalSource, QAfterFilterCondition>
  payloadEndsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.endsWith(
          property: r'payload',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<JournalSource, JournalSource, QAfterFilterCondition>
  payloadContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.contains(
          property: r'payload',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<JournalSource, JournalSource, QAfterFilterCondition>
  payloadMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.matches(
          property: r'payload',
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<JournalSource, JournalSource, QAfterFilterCondition>
  payloadIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'payload', value: ''),
      );
    });
  }

  QueryBuilder<JournalSource, JournalSource, QAfterFilterCondition>
  payloadIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(property: r'payload', value: ''),
      );
    });
  }

  QueryBuilder<JournalSource, JournalSource, QAfterFilterCondition>
  profileIdEqualTo(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'profileId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<JournalSource, JournalSource, QAfterFilterCondition>
  profileIdGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'profileId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<JournalSource, JournalSource, QAfterFilterCondition>
  profileIdLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'profileId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<JournalSource, JournalSource, QAfterFilterCondition>
  profileIdBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'profileId',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<JournalSource, JournalSource, QAfterFilterCondition>
  profileIdStartsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.startsWith(
          property: r'profileId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<JournalSource, JournalSource, QAfterFilterCondition>
  profileIdEndsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.endsWith(
          property: r'profileId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<JournalSource, JournalSource, QAfterFilterCondition>
  profileIdContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.contains(
          property: r'profileId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<JournalSource, JournalSource, QAfterFilterCondition>
  profileIdMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.matches(
          property: r'profileId',
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<JournalSource, JournalSource, QAfterFilterCondition>
  profileIdIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'profileId', value: ''),
      );
    });
  }

  QueryBuilder<JournalSource, JournalSource, QAfterFilterCondition>
  profileIdIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(property: r'profileId', value: ''),
      );
    });
  }

  QueryBuilder<JournalSource, JournalSource, QAfterFilterCondition>
  sourceIdEqualTo(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'sourceId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<JournalSource, JournalSource, QAfterFilterCondition>
  sourceIdGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'sourceId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<JournalSource, JournalSource, QAfterFilterCondition>
  sourceIdLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'sourceId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<JournalSource, JournalSource, QAfterFilterCondition>
  sourceIdBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'sourceId',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<JournalSource, JournalSource, QAfterFilterCondition>
  sourceIdStartsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.startsWith(
          property: r'sourceId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<JournalSource, JournalSource, QAfterFilterCondition>
  sourceIdEndsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.endsWith(
          property: r'sourceId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<JournalSource, JournalSource, QAfterFilterCondition>
  sourceIdContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.contains(
          property: r'sourceId',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<JournalSource, JournalSource, QAfterFilterCondition>
  sourceIdMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.matches(
          property: r'sourceId',
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<JournalSource, JournalSource, QAfterFilterCondition>
  sourceIdIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'sourceId', value: ''),
      );
    });
  }

  QueryBuilder<JournalSource, JournalSource, QAfterFilterCondition>
  sourceIdIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(property: r'sourceId', value: ''),
      );
    });
  }

  QueryBuilder<JournalSource, JournalSource, QAfterFilterCondition>
  targetEqualTo(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(
          property: r'target',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<JournalSource, JournalSource, QAfterFilterCondition>
  targetGreaterThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(
          include: include,
          property: r'target',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<JournalSource, JournalSource, QAfterFilterCondition>
  targetLessThan(
    String value, {
    bool include = false,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.lessThan(
          include: include,
          property: r'target',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<JournalSource, JournalSource, QAfterFilterCondition>
  targetBetween(
    String lower,
    String upper, {
    bool includeLower = true,
    bool includeUpper = true,
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.between(
          property: r'target',
          lower: lower,
          includeLower: includeLower,
          upper: upper,
          includeUpper: includeUpper,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<JournalSource, JournalSource, QAfterFilterCondition>
  targetStartsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.startsWith(
          property: r'target',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<JournalSource, JournalSource, QAfterFilterCondition>
  targetEndsWith(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.endsWith(
          property: r'target',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<JournalSource, JournalSource, QAfterFilterCondition>
  targetContains(String value, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.contains(
          property: r'target',
          value: value,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<JournalSource, JournalSource, QAfterFilterCondition>
  targetMatches(String pattern, {bool caseSensitive = true}) {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.matches(
          property: r'target',
          wildcard: pattern,
          caseSensitive: caseSensitive,
        ),
      );
    });
  }

  QueryBuilder<JournalSource, JournalSource, QAfterFilterCondition>
  targetIsEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.equalTo(property: r'target', value: ''),
      );
    });
  }

  QueryBuilder<JournalSource, JournalSource, QAfterFilterCondition>
  targetIsNotEmpty() {
    return QueryBuilder.apply(this, (query) {
      return query.addFilterCondition(
        FilterCondition.greaterThan(property: r'target', value: ''),
      );
    });
  }
}

extension JournalSourceQueryObject
    on QueryBuilder<JournalSource, JournalSource, QFilterCondition> {}

extension JournalSourceQueryLinks
    on QueryBuilder<JournalSource, JournalSource, QFilterCondition> {}

extension JournalSourceQuerySortBy
    on QueryBuilder<JournalSource, JournalSource, QSortBy> {
  QueryBuilder<JournalSource, JournalSource, QAfterSortBy>
  sortByConnectionRevision() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'connectionRevision', Sort.asc);
    });
  }

  QueryBuilder<JournalSource, JournalSource, QAfterSortBy>
  sortByConnectionRevisionDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'connectionRevision', Sort.desc);
    });
  }

  QueryBuilder<JournalSource, JournalSource, QAfterSortBy> sortByEnabled() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'enabled', Sort.asc);
    });
  }

  QueryBuilder<JournalSource, JournalSource, QAfterSortBy> sortByEnabledDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'enabled', Sort.desc);
    });
  }

  QueryBuilder<JournalSource, JournalSource, QAfterSortBy> sortByKind() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'kind', Sort.asc);
    });
  }

  QueryBuilder<JournalSource, JournalSource, QAfterSortBy> sortByKindDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'kind', Sort.desc);
    });
  }

  QueryBuilder<JournalSource, JournalSource, QAfterSortBy> sortByName() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'name', Sort.asc);
    });
  }

  QueryBuilder<JournalSource, JournalSource, QAfterSortBy> sortByNameDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'name', Sort.desc);
    });
  }

  QueryBuilder<JournalSource, JournalSource, QAfterSortBy> sortByPayload() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'payload', Sort.asc);
    });
  }

  QueryBuilder<JournalSource, JournalSource, QAfterSortBy> sortByPayloadDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'payload', Sort.desc);
    });
  }

  QueryBuilder<JournalSource, JournalSource, QAfterSortBy> sortByProfileId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'profileId', Sort.asc);
    });
  }

  QueryBuilder<JournalSource, JournalSource, QAfterSortBy>
  sortByProfileIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'profileId', Sort.desc);
    });
  }

  QueryBuilder<JournalSource, JournalSource, QAfterSortBy> sortBySourceId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'sourceId', Sort.asc);
    });
  }

  QueryBuilder<JournalSource, JournalSource, QAfterSortBy>
  sortBySourceIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'sourceId', Sort.desc);
    });
  }

  QueryBuilder<JournalSource, JournalSource, QAfterSortBy> sortByTarget() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'target', Sort.asc);
    });
  }

  QueryBuilder<JournalSource, JournalSource, QAfterSortBy> sortByTargetDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'target', Sort.desc);
    });
  }
}

extension JournalSourceQuerySortThenBy
    on QueryBuilder<JournalSource, JournalSource, QSortThenBy> {
  QueryBuilder<JournalSource, JournalSource, QAfterSortBy>
  thenByConnectionRevision() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'connectionRevision', Sort.asc);
    });
  }

  QueryBuilder<JournalSource, JournalSource, QAfterSortBy>
  thenByConnectionRevisionDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'connectionRevision', Sort.desc);
    });
  }

  QueryBuilder<JournalSource, JournalSource, QAfterSortBy> thenByEnabled() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'enabled', Sort.asc);
    });
  }

  QueryBuilder<JournalSource, JournalSource, QAfterSortBy> thenByEnabledDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'enabled', Sort.desc);
    });
  }

  QueryBuilder<JournalSource, JournalSource, QAfterSortBy> thenById() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.asc);
    });
  }

  QueryBuilder<JournalSource, JournalSource, QAfterSortBy> thenByIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'id', Sort.desc);
    });
  }

  QueryBuilder<JournalSource, JournalSource, QAfterSortBy> thenByKind() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'kind', Sort.asc);
    });
  }

  QueryBuilder<JournalSource, JournalSource, QAfterSortBy> thenByKindDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'kind', Sort.desc);
    });
  }

  QueryBuilder<JournalSource, JournalSource, QAfterSortBy> thenByName() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'name', Sort.asc);
    });
  }

  QueryBuilder<JournalSource, JournalSource, QAfterSortBy> thenByNameDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'name', Sort.desc);
    });
  }

  QueryBuilder<JournalSource, JournalSource, QAfterSortBy> thenByPayload() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'payload', Sort.asc);
    });
  }

  QueryBuilder<JournalSource, JournalSource, QAfterSortBy> thenByPayloadDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'payload', Sort.desc);
    });
  }

  QueryBuilder<JournalSource, JournalSource, QAfterSortBy> thenByProfileId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'profileId', Sort.asc);
    });
  }

  QueryBuilder<JournalSource, JournalSource, QAfterSortBy>
  thenByProfileIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'profileId', Sort.desc);
    });
  }

  QueryBuilder<JournalSource, JournalSource, QAfterSortBy> thenBySourceId() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'sourceId', Sort.asc);
    });
  }

  QueryBuilder<JournalSource, JournalSource, QAfterSortBy>
  thenBySourceIdDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'sourceId', Sort.desc);
    });
  }

  QueryBuilder<JournalSource, JournalSource, QAfterSortBy> thenByTarget() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'target', Sort.asc);
    });
  }

  QueryBuilder<JournalSource, JournalSource, QAfterSortBy> thenByTargetDesc() {
    return QueryBuilder.apply(this, (query) {
      return query.addSortBy(r'target', Sort.desc);
    });
  }
}

extension JournalSourceQueryWhereDistinct
    on QueryBuilder<JournalSource, JournalSource, QDistinct> {
  QueryBuilder<JournalSource, JournalSource, QDistinct>
  distinctByConnectionRevision() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'connectionRevision');
    });
  }

  QueryBuilder<JournalSource, JournalSource, QDistinct> distinctByEnabled() {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'enabled');
    });
  }

  QueryBuilder<JournalSource, JournalSource, QDistinct> distinctByKind({
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'kind', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<JournalSource, JournalSource, QDistinct> distinctByName({
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'name', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<JournalSource, JournalSource, QDistinct> distinctByPayload({
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'payload', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<JournalSource, JournalSource, QDistinct> distinctByProfileId({
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'profileId', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<JournalSource, JournalSource, QDistinct> distinctBySourceId({
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'sourceId', caseSensitive: caseSensitive);
    });
  }

  QueryBuilder<JournalSource, JournalSource, QDistinct> distinctByTarget({
    bool caseSensitive = true,
  }) {
    return QueryBuilder.apply(this, (query) {
      return query.addDistinctBy(r'target', caseSensitive: caseSensitive);
    });
  }
}

extension JournalSourceQueryProperty
    on QueryBuilder<JournalSource, JournalSource, QQueryProperty> {
  QueryBuilder<JournalSource, int, QQueryOperations> idProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'id');
    });
  }

  QueryBuilder<JournalSource, int, QQueryOperations>
  connectionRevisionProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'connectionRevision');
    });
  }

  QueryBuilder<JournalSource, bool, QQueryOperations> enabledProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'enabled');
    });
  }

  QueryBuilder<JournalSource, String, QQueryOperations> kindProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'kind');
    });
  }

  QueryBuilder<JournalSource, String, QQueryOperations> nameProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'name');
    });
  }

  QueryBuilder<JournalSource, String, QQueryOperations> payloadProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'payload');
    });
  }

  QueryBuilder<JournalSource, String, QQueryOperations> profileIdProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'profileId');
    });
  }

  QueryBuilder<JournalSource, String, QQueryOperations> sourceIdProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'sourceId');
    });
  }

  QueryBuilder<JournalSource, String, QQueryOperations> targetProperty() {
    return QueryBuilder.apply(this, (query) {
      return query.addPropertyName(r'target');
    });
  }
}
