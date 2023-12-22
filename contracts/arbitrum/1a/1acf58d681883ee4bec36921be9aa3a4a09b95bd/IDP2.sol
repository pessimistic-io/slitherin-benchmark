interface IDP2 {
    function trustedMinter() external;

    function nextMintId() external;

    function publicMints() external;

    function maxPublicMints() external;

    function mint(uint256 number, address receiver) external;
}
