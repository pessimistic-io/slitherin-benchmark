interface IDuelPepesWhitelist {
    function isWhitelistActive() external returns (bool);

    function isWhitelisted(address duellor) external returns (bool);
}
