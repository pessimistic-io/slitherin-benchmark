// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

interface IFaucet1 { 

    function deposit(
        address payable[] memory addr,
        uint amount,
        uint otherFees, 
        uint endDate,
        uint target, 
        bool[] memory features,
        string memory uuid
    ) 
        external payable;

    // function swapBeforeDeposit(
    //     address _token,
    //     address payable[] memory addr,
    //     uint _amount,
    //     uint _otherFees,
    //     uint _endDate,
    //     uint _target,
    //     bool [] memory features,
    //     string memory uuid)  external;

    function submitBeneficiary(uint id, string memory message, bytes memory signature, address signer,address _stableCoin,address receiver) external;

    function bulkClaim(uint[] memory ids, address SWAPTOKEN) external returns(bool);

    function claim(uint256 id, address SWAPTOKEN) external;

    // function swap (address _tokenIn, address _tokenOut,uint _amount, address _to) internal returns (bool success);

    function transferBeneficiary(address _newBeneficiary, uint _assetId) external;

}   
