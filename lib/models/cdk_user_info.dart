class CdkUserInfo {
  final int id;
  final String username;
  final String nickname;
  final int trustLevel;
  final String avatarUrl;
  final int score;

  CdkUserInfo({
    required this.id,
    required this.username,
    required this.nickname,
    required this.trustLevel,
    required this.avatarUrl,
    required this.score,
  });

  factory CdkUserInfo.fromJson(Map<String, dynamic> json) {
    return CdkUserInfo(
      id: json['id'] as int,
      username: json['username'] as String,
      nickname: json['nickname'] as String,
      trustLevel: json['trust_level'] as int,
      avatarUrl: json['avatar_url'] as String,
      score: json['score'] as int,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'username': username,
      'nickname': nickname,
      'trust_level': trustLevel,
      'avatar_url': avatarUrl,
      'score': score,
    };
  }
}
