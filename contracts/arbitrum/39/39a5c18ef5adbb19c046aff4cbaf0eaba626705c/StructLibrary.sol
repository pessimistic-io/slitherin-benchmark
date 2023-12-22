// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

struct CollectionInfo {
    string banner;
    string logo;
    string name;
    string symbol;
    string tokenImg;
    string fileExtension;
    string baseImgURI;
    string[] socials;
    uint256 totalSupply;
    uint256[2] fee;
    address artist;
    uint256 mintableNFTs;
    string _type;
    address tokenDeployed;
    uint256 apr;
}

struct Socials {
    string banner;
    string logo;
    string name;
    string symbol;
    string tokenImg;
    string fileExtension;
    string baseImgURI;
    string[] socials;
    address artist;
    string _type;
}

struct DeploymentParams {
    string name;
    string symbol;
    string[] uris;
    uint256 supplyBASE;
    uint256 supplyGBT;
    address base;
    address artist;
    uint256 delay;
    uint256[] fees;
}

struct UserData {
    uint256 currentPrice;
    uint256[] stakedNFTs;
    uint256[] unstakedNFTs;
    uint256 balanceOfBase;
    uint256 stakedGBTs;
    uint256 unstakedGBTs;
    uint256 debt;                 
    uint256 ltv;                  
    uint256 borrowAmountAvailable;
    uint256 mintableNFTs;
    string _type;
    uint256 apr;
    Rewards rewards;
}

struct ZapInParams {
    address gbtForCollection;
    uint256 amountBaseIn;
    uint256 amountNftOut;
    address affiliate;
    bool swapForExact;
    uint256[] ids;
}

struct ZapOutParams {
    address gbtForCollection;
    uint256 amountNftIn;
    uint256 amountBaseOut;
    uint256[] ids;
}

struct ZapParams {
    address gbtForCollection;
    address tokenIn;
    address tokenOut;
    uint256 amountIn;
    uint256 amountOut;
    address affiliate;
    bool swapForExact;
    uint256[] ids;
}

struct CollectionPage {
    CollectionInfo collection;
    BaseTokenInfo base;
    uint256 apr;
}

struct IndividualCollection {
    CollectionInfo collection;
    BaseTokenInfo base;
    uint256 totalSupply;
}

struct BaseTokenInfo {
    address token;
    string symbol;
    uint256 decimals;
    uint256 currentPrice;
}

struct Rewards {
    Token[] rewardTokens;
}

struct Token {
    address addr;
    string symbol;
    uint256 amount;
    uint256 decimals;
}

struct BaseLocked {
    address token;
    string symbol;
    uint256 decimals;
    uint256 lockedAmount;
}
