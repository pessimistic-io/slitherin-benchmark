interface IDP2Mint {
    function mintPrice() external returns (uint);

    function discountedMintPrice() external returns (uint);

    function mint(uint256 number, address receiver) external payable;

    function isWhitelistActive() external returns (bool);

    function isWhitelisted(address duellor) external returns (bool);
}
