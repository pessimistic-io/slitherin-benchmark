// SPDX-License-Identifier: MIT

pragma solidity 0.8.13;

interface IRiskVault {
    function stake(uint256 _amount) external payable;
    function withdraw_request(uint256 _amount) external payable;
    function withdraw(uint256 _amount) external;

    function stakeByGov(uint256 _amount) external;
    function withdrawRequestByGov(uint256 _amount) external;
    function withdrawByGov(uint256 _amount) external;

    function supplyBorrow(uint256 _supplyAmount, uint256 _borrowAmount, uint16 _referralCode) external;
    function repayWithdraw(uint256 _repayAmount, uint256 _withdrawAmount) external;

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
    function setGlpFee(uint256 _glpInFee, uint256 _glpOutFee) external;

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
    function fee() external view returns (uint256);
    function glpInFee() external view returns (uint256);
    function glpOutFee() external view returns (uint256);
}
    
