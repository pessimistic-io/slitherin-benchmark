pragma solidity >=0.8.4;

struct ReferralInfo {
    address referrerAddress;
    bytes32 referrerNodehash;
    uint256 referralAmount;
    uint256 signedAt;
    bytes signature;
}

struct RegInfo {
    address owner;
    uint duration;
    address resolver;
    bool isUsePoints;
    bool isSetPrimaryName;
    uint256 paidFee;
}
