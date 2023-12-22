// SPDX-License-Identifier: MIT

pragma solidity 0.8.11;

interface IGeniVault {
    function getBotKeeper(address _account) external returns (bool);

    function getReferralCode() external returns(bytes32);

    function getReferrer(address _user) external returns(address);

    function getRefLevelFee(address _referrer) external returns(uint256);

    function getBotExecutionFee() external returns(uint256);
    
    function claimPendingRevenue(address _token) external;
    
    function botRequestToken(address _account, uint256 _amount) external returns(uint256);

    function getMarginFeeBasisPoints() external returns(uint256);

    function botRequestUpdateBalanceAndFees(
        address _account, 
        address _trader, 
        uint256 _amount, 
        uint256 _realisedPnl, 
        bool _isRealisedPnl
    ) external returns(uint256);

    function botRequestUpdateBalance(
        address _account, 
        uint256 _amount
    ) external;

    function botRequestUpdateFees(
        address _account, 
        address _trader, 
        uint256 _realisedPnl, 
        bool _isRealisedPnl
    ) external returns(uint256);
}

