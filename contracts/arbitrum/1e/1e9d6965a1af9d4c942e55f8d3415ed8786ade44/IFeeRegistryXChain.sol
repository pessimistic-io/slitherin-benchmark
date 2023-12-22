// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface IFeeRegistryXChain {
    enum MANAGEFEE {
		PERFFEE,
		VESDTFEE,
		ACCUMULATORFEE,
		CLAIMERREWARD
	}
    function BASE_FEE() external returns(uint256);
    function manageFee(MANAGEFEE, address, address, uint256) external;
    function manageFees(MANAGEFEE[] calldata, address[] calldata, address[] calldata, uint256[] calldata) external; 
    function getFee(address, address, MANAGEFEE) external view returns(uint256);
}
