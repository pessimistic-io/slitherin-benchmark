// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./Ownable.sol";
import "./IERC20.sol";

import "./Token.sol";

/// @title TaxCollector
/// @dev This contract collects taxes from transactions and distributes them
/// to different addresses such as the treasury and management.
contract TaxCollector is Ownable {
    DaikokuDAO public immutable token;

    // Treasury
    address public treasury;
    // Management fees
    address public managementFeeAddress1;
    address public managementFeeAddress2;
    uint256 public managementSharePercentage = 20;

    /// @notice Constructs the TaxCollector contract.
    /// @param _token The address of the token contract
    /// @param _treasury The address where the treasury funds will be sent
    /// @param _managementFeeAddress1 The first address where the management fees will be sent
    /// @param _managementFeeAddress2 The second address where the management fees will be sent
    constructor(
	address _token,
	address _treasury,
	address _managementFeeAddress1,
	address _managementFeeAddress2
    ) {
	require(_token != address(0), "Token is the zero address");
	require(_treasury != address(0), "Treasury is the zero address");
	require(_managementFeeAddress1 != address(0), "Management1 is the zero address");
	require(_managementFeeAddress2 != address(0), "Management2 is the zero address");

	token = DaikokuDAO(_token);
	treasury = _treasury;
	managementFeeAddress1 = _managementFeeAddress1;
	managementFeeAddress2 = _managementFeeAddress2;
    }

    /// @notice Sets treasury and management addresses
    /// @param _treasury New treasury address
    /// @param _management1 New management address 1
    /// @param _management2 New management address 2
     function setAddresses(address _treasury, address _management1, address _management2) external onlyOwner {
	require(_treasury != address(0), "treasury is the zero address");
	require(_management1 != address(0), "management1 is the zero address");
	require(_management2 != address(0), "management2 is the zero address");

	treasury = _treasury;
	managementFeeAddress1 = _management1;
	managementFeeAddress2 = _management2;
    }

    /// @notice Sets management percentage for fee distribution
    /// @param _percentage The percentage to be assigned to management
    function setManagementPercentage(uint256 _percentage) external onlyOwner {
	require(_percentage <= 100, "Percentage must not exceed 100");
	managementSharePercentage = _percentage;
    }

    /// @notice Distributes collected tax to management and treasury addresses
    /// @param tax The amount of tax collected that needs to be distributed
    function distributeCollectedTax(uint256 tax) external {
	require(msg.sender == owner() || msg.sender == address(token), "Only token contract can call");

	// Distribute the tax to the management fee addresses
	if (managementSharePercentage > 0) {
	    uint256 managementFeeShare = (tax * managementSharePercentage) / 100;
	    uint256 managementFeeHalf = managementFeeShare / 2;
	    token.transferWithoutTax(address(this), managementFeeAddress1, managementFeeHalf);
	    token.transferWithoutTax(address(this), managementFeeAddress2, managementFeeShare - managementFeeHalf);
	}

	// Distribute the tax to the treasury
	uint256 treasurySharePercentage = 100 - managementSharePercentage;
	if (treasurySharePercentage > 0) {
	    uint256 treasuryShare = (tax * treasurySharePercentage) / 100;
	    token.transferWithoutTax(address(this), treasury, treasuryShare);
	}
    }

    /// @notice Rescue funds in the tax collector and send to the treasury
    function rescueFundsToTreasury() external onlyOwner {
	// Withdraw all the token balance to the treasury
	uint256 tokenBalance = token.balanceOf(address(this));
	if (tokenBalance > 0) {
	    token.transferWithoutTax(address(this), treasury, tokenBalance);
	}

	// Withdraw all the ETH balance to the treasury
	uint256 ethBalance = address(this).balance;
	if (ethBalance > 0) {
	    (bool success, ) = treasury.call{value: ethBalance}("");
	    require(success, "ETH transfer failed");
	}
    }

    receive() external payable {}
}

