pragma solidity >=0.5.0;

interface ICErc20 {
    function initialize(
        address underlying_,
        address comptroller_,
        address interestRateModel_,
        uint initialExchangeRateMantissa_,
        string memory name_,
        string memory symbol_,
        uint8 decimals_
    ) external;

    function mintFor(uint256 mintAmount, address to) external returns(uint);
}

