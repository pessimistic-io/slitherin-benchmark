interface IDuelPepesLeaderboard {
    function updateNftLeaderboard(
      uint id,
      bool isDraw,
      uint creatorDamage,
      uint challengerDamage
    ) external;

    function updateUserLeaderboard(
      uint id,
      bool isDraw,
      uint creatorDamage,
      uint challengerDamage
    ) external;

    function getCreditForMinting(address duellor)
    external
    view
    returns(uint);

    function charge(address duellor, uint expense)
    external;
}
