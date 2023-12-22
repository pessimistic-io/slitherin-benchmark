interface IDuelPepesLogic {
    function decideDuel(
      uint id
    )
    external
    view
    returns (uint creatorDamage, uint challengerDamage);

    function verify(
      bytes32 data,
      bytes memory signature,
      address account
    ) external pure returns (bool);
}
