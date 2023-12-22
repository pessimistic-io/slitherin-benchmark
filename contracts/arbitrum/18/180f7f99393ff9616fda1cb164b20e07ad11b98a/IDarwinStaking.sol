pragma solidity ^0.8.14;

interface IDarwinStaking {

    struct UserInfo {
        uint lastClaimTimestamp;
        uint lockStart;
        uint lockEnd;
        uint boost; // (1, 5, 10, 25, 50)
        address nft;
        uint tokenId;
    }

    event Stake(address indexed user, uint indexed amount);
    event Withdraw(address indexed user, uint indexed amount, uint indexed rewards);

    event StakeEvoture(address indexed user, uint indexed evotureTokenId, uint indexed multiplier);
    event WithdrawEvoture(address indexed user, uint indexed evotureTokenId);

    function getUserInfo(address _user) external view returns (UserInfo memory);
}
