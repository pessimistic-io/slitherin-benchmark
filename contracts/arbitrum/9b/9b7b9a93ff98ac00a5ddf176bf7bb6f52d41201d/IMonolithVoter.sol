pragma solidity 0.8.16;

interface IMonolithVoter {
    function setTokenID(uint256 tokenID) external returns (bool);

    function userVotes(address user, uint256 week)
        external
        returns (uint256);
}

