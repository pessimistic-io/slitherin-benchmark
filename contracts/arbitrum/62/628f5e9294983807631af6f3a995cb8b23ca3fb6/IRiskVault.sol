// SPDX-License-Identifier: MIT

pragma solidity 0.8.13;

interface IRiskVault {
    function stake(uint256 _amount) external payable;
    function withdraw_request(uint256 _amount) external payable;
    function withdraw(uint256 _amount) external;

    function supplyBorrowAave( address _supplyToken, uint256 _supplyAmount, address _borrowToken, uint256 _borrowAmount, uint16 _referralCode) external;
    function supplyAave( address _supplyToken, uint256 _supplyAmount, uint16 _referralCode) external;
    function borrowAave( address _borrowToken, uint256 _borrowAmount, uint16 _referralCode) external;
    
    function repayWithdrawAave(address _repayToken, uint256 _repayAmount, address _withdrawToken, uint256 _withdrawAmount) external;
    function repayAave(address _repayToken, uint256 _repayAmount) external;
    function withdrawAave(address _withdrawToken, uint256 _withdrawAmount) external;

    function treasuryWithdrawFunds(address _token, uint256 amount, address to) external;
    function treasuryWithdrawFundsWETHToETH(uint256 amount, address to) external;
    function treasuryWithdrawFundsETH(uint256 amount, address to) external;

    function allocateReward(int256 amount) external;
    function handleStakeRequest(address[] memory _address) external;
    function handleWithdrawRequest(address[] memory _address) external;

    function removeWithdrawRequest(address[] memory _address) external;
    function setCapacity(uint256 _capacity) external;
    function setAaveUserEMode(uint8 categoryId) external;

    function pause() external;
    function unpause() external;
    function setFee(uint256 _inFee, uint256 _outFee) external;

    function balance_wait(address account) external view returns (uint256);
    function balance_staked(address account) external view returns (uint256);
    function balance_withdraw(address account) external view returns (uint256);
    function balance_reward(address account) external view returns (int256);

    function total_supply_wait() external view returns (uint256);
    function total_supply_staked() external view returns (uint256);
    function total_supply_withdraw() external view returns (uint256);
    function total_supply_reward() external view returns (int256);

    function share_price()external view returns (uint256);
    function share_price_decimals()external view returns (uint256);

    function gasthreshold() external view returns (uint256);
    function protocolFee() external view returns (uint256);
    function inFee() external view returns (uint256);
    function outFee() external view returns (uint256);
}
    
