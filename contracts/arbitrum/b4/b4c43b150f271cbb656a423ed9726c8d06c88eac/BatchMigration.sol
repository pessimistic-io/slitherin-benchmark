// SPDX-License-Identifier: MIT

pragma solidity 0.8.11;

import "./Ownable.sol";
import "./IERC20.sol";

contract BatchMigration is Ownable {
    function batchAction(address _contract, bytes4 _selector, bytes[] calldata _params) external onlyOwner {
        uint256 length = _params.length;
        for (uint256 i = 0; i < length; i++) {
            // console.logBytes(abi.encodePacked(_selector, _params[i]));
            (bool success, )= _contract.call(abi.encodePacked(_selector, _params[i]));
            
            require(success, "call action failed");
        }
    }

    function withdrawToken(address _token, address _account, uint256 _amount) external onlyOwner {
        IERC20(_token).transfer(_account, _amount);
    }
}
