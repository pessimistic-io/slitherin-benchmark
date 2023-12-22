// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.7.6;

interface IICHIVaultFactory {

    event FeeRecipient(
        address indexed sender, 
        address feeRecipient);

    event BaseFee(
        address indexed sender, 
        uint256 baseFee);

    event BaseFeeSplit(
        address indexed sender, 
        uint256 baseFeeSplit);
    
    event VeRamTokenId(
        address indexed sender, 
        uint256 veRamTokenId);

    event DeployICHIVaultFactory(
        address indexed sender, 
        address ramsesV2Factory);

    event ICHIVaultCreated(
        address indexed sender, 
        address ichiVault, 
        address tokenA,
        bool allowTokenA,
        address tokenB,
        bool allowTokenB,
        uint24 fee,
        uint256 count);    

    function ramsesV2Factory() external view returns(address);
    function ramsesV2GaugeFactory() external view returns(address);
    function veRamTokenId() external view returns(uint256);
    function feeRecipient() external view returns(address);
    function baseFee() external view returns(uint256);
    function baseFeeSplit() external view returns(uint256);
    
    function setFeeRecipient(address _feeRecipient) external;
    function setBaseFee(uint256 _baseFee) external;
    function setBaseFeeSplit(uint256 _baseFeeSplit) external;
    function setVeRamTokenId(uint256 _veRamTokenId) external;

    function createICHIVault(
        address tokenA,
        bool allowTokenA,
        address tokenB,
        bool allowTokenB,
        uint24 fee
    ) external returns (address ichiVault);

    function genKey(
        address deployer, 
        address token0, 
        address token1, 
        uint24 fee, 
        bool allowToken0, 
        bool allowToken1) external pure returns(bytes32 key);
}

