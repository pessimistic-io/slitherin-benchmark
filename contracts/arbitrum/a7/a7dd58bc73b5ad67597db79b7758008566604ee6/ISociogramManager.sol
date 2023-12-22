// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./IERC20.sol";

interface ISociogramManager {
    function pause() external;
    function unpause() external;

    // Setters
    function setServer(address _newServerAddress) external;
    function setTeamRewardTreasury(address _treasuryAddress) external;
    function setTeamRewardFeePercent(uint256 _newPercent) external;
    function setIssuerFeePercent(uint256 _newPercent) external;
   
    function issueToken(
        bytes calldata _signature,
        string calldata _twitterId,
        uint256 _premintAmount,
        uint256 _maximumPayed,
        uint256 _expirationTimestamp
    ) external;
    function buyTokens(
        address _token,
        uint256 _amount,
        uint256 _maximumPayed,
        uint256 _deadline
    ) external;
    function sellTokens(
        address _token,
        uint256 _amount,
        uint256 _minimumReceived,
        uint256 _deadline
    ) external;

    // Getters
    function getPrice(uint256 supply, uint256 amount) external pure returns (uint256);
    function getBuyPrice(address _token, uint256 _amount) external view returns (uint256);
    function getSellPrice(address _token, uint256 _amount) external view returns (uint256);
    function getBuyPriceAfterFee(address _token, uint256 _amount) external view returns (uint256, uint256, uint256, uint256);
    function getSellPriceAfterFee(address _token, uint256 _amount) external view returns (uint256, uint256, uint256, uint256);

    // View functions
    function server() external view returns (address);
    function teamRewardTreasury() external view returns (address);
    function teamRewardFeePercent() external view returns (uint256);
    function issuerFeePercent() external view returns (uint256);
    function BASE_TOKEN() external view returns (IERC20);
    function executed(bytes32) external view returns (bool);
    function issuedTokensMap(address) external view returns (address);
    function issuedTokens(uint256) external view returns (address);
    function issuedTokensCount() external view returns (uint256);
}
