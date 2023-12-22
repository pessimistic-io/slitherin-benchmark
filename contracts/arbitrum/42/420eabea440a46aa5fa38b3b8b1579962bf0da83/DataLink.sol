// SPDX-License-Identifier: MIT
pragma solidity  ^0.8.0;
pragma abicoder v2;

import { Initializable } from "./Initializable.sol";
import { IDataVault } from "./IDataVault.sol";
import { NonblockingLzApp } from "./NonblockingLzApp.sol";
import {ILayerZeroEndpoint} from "./ILayerZeroEndpoint.sol";

contract DataLink is Initializable, NonblockingLzApp {
    struct Message {
        uint256 id;
        address vault;
        uint256 balance;
        uint256 tvl;
        uint256 chainId;
        uint256 timestamp;
        uint8 source;
        address[2] _gap_address;
        uint256[2] _gap_uint256;
        bool[2] _gap_bool;
    }
    
    address[] public vaults;
    uint16 public dataStoreChain; // Not actual blockchain chaindId

    event Shoot(uint16 _lzChainId, bytes  _srcAddress, bytes  _payload);
    function initialize(address _endpoint, uint16 _dataStoreChain) external onlyGovernor initializer {
        lzEndpoint = ILayerZeroEndpoint(_endpoint);
        dataStoreChain = _dataStoreChain;
    }

    function setDatastoreChain(uint16 _dataStoreChain) external onlyGovernor {
        dataStoreChain = _dataStoreChain;
    }
    function addVault(address _vault) external onlyGovernor{
        vaults.push(_vault);
    }
    function removeVault(address _vault) external onlyGovernor {
        for (uint256 i = 0; i < vaults.length; i++) {
            if (vaults[i] == _vault) {
                vaults[i] = vaults[vaults.length - 1];
                vaults.pop();
                break;
            }
        }
    }


    function balance(address _vault) external view returns (uint256) {
        require(_vaultExist(_vault), "!vault");
        return IDataVault(_vault).balance();
    }

    function tvl(address _vault) external view returns (uint256) {
        require(_vaultExist(_vault), "!vault");
        return IDataVault(_vault).tvl();
    }
    function _vaultExist(address _vault) internal view returns (bool) {
        for (uint256 i = 0; i < vaults.length; i++) {
            if (vaults[i] == _vault) {
                return true;
            }
        }
        return false;
    }
    function getChainID() internal view returns (uint256) {
        uint256 id;
        assembly {
            id := chainid()
        }
        return id;
    }
    function _payload() internal view returns (address[] memory, uint256[] memory, uint256[] memory) {
        uint256[] memory balances = new uint256[](vaults.length);
        uint256[] memory tvls = new uint256[](vaults.length);
        for (uint256 i = 0; i < vaults.length; i++) {
            balances[i] = IDataVault(vaults[i]).balance();
            tvls[i] = IDataVault(vaults[i]).tvl();
        }
        return (vaults, balances, tvls);
    }
    function shoot() public payable {
        require(address(this).balance > 0, "the balance of this contract is 0. pls send gas for message fees");


        // Load the truck
        (address[] memory _vaults, uint256[] memory _balances, uint256[] memory _tvls) = _payload();
        bytes memory payload = abi.encode(_vaults, _balances, _tvls, getChainID(), block.timestamp);

        // use adapterParams v1 to specify more gas for the destination
        uint16 version = 1;
        uint gasForDestinationLzReceive = 500000;
        bytes memory adapterParams = abi.encodePacked(version, gasForDestinationLzReceive);

        (uint messageFee, ) = lzEndpoint.estimateFees(dataStoreChain, address(this), payload, false, adapterParams);
        messageFee = messageFee * 3 / 2;
        require(address(this).balance >= messageFee, "address(this).balance < messageFee. fund this contract with more ether");

        bytes memory trustedRemote = trustedRemoteLookup[dataStoreChain];

        // send LayerZero message
        lzEndpoint.send{value: messageFee}( // {value: messageFee} will be paid out of this contract!
            dataStoreChain, // destination chainId
            trustedRemote, // destination address of PingPong contract
            payload, // abi.encode()'ed bytes
            payable(this), // (msg.sender will be this contract) refund address (LayerZero will refund any extra gas back to caller of send()
            address(0x0), // future param, unused for this example
            adapterParams // v1 adapterParams, specify custom destination gas qty
        );
        emit Shoot(dataStoreChain, trustedRemote, payload);
    }
    receive() external payable {}
    
    function _nonblockingLzReceive(uint16, bytes memory, uint64, bytes memory) internal override {
        revert("Unused");
    }
    
   
}
