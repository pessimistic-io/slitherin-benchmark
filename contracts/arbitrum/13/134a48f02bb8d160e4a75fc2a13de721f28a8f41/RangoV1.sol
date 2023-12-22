// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.13;

import "./BaseProxyContract.sol";
import "./RangoCBridgeProxy.sol";
import "./RangoThorchainProxy.sol";
import "./RangoMultichainProxy.sol";
import "./RangoHyphenProxy.sol";
import "./RangoAcrossProxy.sol";
import "./RangoHopProxy.sol";
import "./RangoSynapseProxy.sol";

/// @title The main contract that users interact with in the source chain
/// @author Uchiha Sasuke
/// @notice It contains all the required functions to swap on-chain or swap + bridge or swap + bridge + swap initiation in a single step
/// @dev To support a new bridge, it inherits from a proxy with the name of that bridge which adds extra function for that specific bridge
/// @dev There are some extra refund functions for admin to get the money back in case of any unwanted problem
/// @dev This contract is being seen via a transparent proxy from openzeppelin
contract RangoV1 is BaseProxyContract, RangoCBridgeProxy, RangoThorchainProxy, RangoMultichainProxy, RangoSynapseProxy, RangoHopProxy, RangoAcrossProxy, RangoHyphenProxy {

    /// @notice Initializes the state of all sub bridges contracts that RangoV1 inherited from
    /// @param _nativeWrappedAddress Address of wrapped token (WETH, WBNB, etc.) on the current chain
    /// @dev It is the initializer function of proxy pattern, and is equivalent to constructor for normal contracts
    function initialize(address _nativeWrappedAddress) public initializer {
        BaseProxyStorage storage baseProxyStorage = getBaseProxyContractStorage();
        CBridgeProxyStorage storage cbridgeProxyStorage = getCBridgeProxyStorage();
        ThorchainProxyStorage storage thorchainProxyStorage = getThorchainProxyStorage();
        MultichainProxyStorage storage multichainProxyStorage = getMultichainProxyStorage();
        HyphenProxyStorage storage hyphenProxyStorage = getHyphenProxyStorage();
        AcrossProxyStorage storage acrossProxyStorage = getAcrossProxyStorage();
        HopProxyStorage storage hopProxyStorage = getHopProxyStorage();
        SynapseProxyStorage storage synapseProxyStorage = getSynapseProxyStorage();
        
        baseProxyStorage.nativeWrappedAddress = _nativeWrappedAddress;
        baseProxyStorage.feeContractAddress = NULL_ADDRESS;
        cbridgeProxyStorage.rangoCBridgeAddress = NULL_ADDRESS;
        thorchainProxyStorage.rangoThorchainAddress = NULL_ADDRESS;
        multichainProxyStorage.rangoMultichainAddress = NULL_ADDRESS;
        hyphenProxyStorage.rangoHyphenAddress = NULL_ADDRESS;
        acrossProxyStorage.rangoAcrossAddress = NULL_ADDRESS;
        hopProxyStorage.rangoHopAddress = NULL_ADDRESS;
        synapseProxyStorage.rangoSynapseAddress = NULL_ADDRESS;

        __Ownable_init();
        __Pausable_init();
        __ReentrancyGuard_init();
    }

    /// @notice Enables the contract to receive native ETH token from other contracts including WETH contract
    receive() external payable { }

    /// @notice Returns the list of valid Rango contracts that can call other contracts for the security purpose
    /// @dev This contains the contracts that can call others via messaging protocols, and excludes DEX-only contracts such as Thorchain
    /// @return List of addresses of Rango contracts that can call other contracts
    function getValidRangoContracts() external view returns (address[] memory) {
        CBridgeProxyStorage storage cbridgeProxyStorage = getCBridgeProxyStorage();
        MultichainProxyStorage storage multichainProxyStorage = getMultichainProxyStorage();
        ThorchainProxyStorage storage thorchainProxyStorage = getThorchainProxyStorage();
        SynapseProxyStorage storage synapseProxyStorage = getSynapseProxyStorage();
        AcrossProxyStorage storage acrossProxyStorage = getAcrossProxyStorage();
        HopProxyStorage storage hopProxyStorage = getHopProxyStorage();
        HyphenProxyStorage storage hyphenProxyStorage = getHyphenProxyStorage();

        address[] memory whitelist = new address[](8);
        whitelist[0] = address(this);
        whitelist[1] = cbridgeProxyStorage.rangoCBridgeAddress;
        whitelist[2] = multichainProxyStorage.rangoMultichainAddress;
        whitelist[3] = synapseProxyStorage.rangoSynapseAddress;
        whitelist[4] = acrossProxyStorage.rangoAcrossAddress;
        whitelist[5] = hopProxyStorage.rangoHopAddress;
        whitelist[6] = thorchainProxyStorage.rangoThorchainAddress;
        whitelist[7] = hyphenProxyStorage.rangoHyphenAddress;

        return whitelist;
    }
}


