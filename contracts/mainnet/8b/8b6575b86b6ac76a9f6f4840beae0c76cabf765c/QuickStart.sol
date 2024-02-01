// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import {IGnosisSafe} from "./IGnosisSafe.sol";

// Safe Quick Start Setup ---* Client does not have a backup address ready *--- //

contract QuickStart {


    function quickStart(
        address _onBehalf, 
        uint _placeholder,
        uint __placeholder,
        bytes calldata _data
    ) 
        public 
        returns (bytes memory txData) 
    {
        (address comptroller, address primary, uint[] memory accountFees) = abi.decode(_data,(address,address,uint[]));
        // Get branch address (for Guardian)
        uint advisorId = IComp(comptroller).advisorToId(IGnosisSafe(_onBehalf).getOwners()[0]);
        address branch = IComp(comptroller).getBranchAddress(IComp(comptroller).getAdvisorBranch(advisorId));

        bytes[] memory actions = new bytes[](3);
        // Add Primary as owner
        actions[0] = abi.encodePacked(uint8(0),_onBehalf,uint256(0),uint256(68),abi.encodeWithSignature(
                "addOwnerWithThreshold(address,uint256)", primary, 2));
        // Add Guardian branch as owner
        actions[1] = abi.encodePacked(uint8(0),_onBehalf,uint256(0),uint256(68),abi.encodeWithSignature(
                "addOwnerWithThreshold(address,uint256)", branch, 2));

        // Update Comptroller
        address[] memory _clientSafes = new address[](1);
        _clientSafes[0] = _onBehalf;

        actions[2] = abi.encodePacked(uint8(0),comptroller,uint256(0),uint256(292),abi.encodeWithSignature(
                "registerUser(address[],uint256[],address,address,uint256)", _clientSafes, accountFees, primary, address(0), advisorId));

        uint len = actions.length;
        for (uint i=0; i< len; ++i){
            txData = abi.encodePacked(txData,actions[i]);
        }

        return txData;
    }

}


interface IComp{
    function advisorToId(address _advisorAddress) external view returns (uint);
    function getBranchAddress(uint _branchId) 
        external
        view
        returns (address);
    function getAdvisorBranch(
        uint256 _advisorId
    )
        external
        view
        returns (uint256);
}
