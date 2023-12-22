// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

import "./ERC20_IERC20Upgradeable.sol";
import "./IComposableOFTCore.sol";

interface IRumiToken is IERC20Upgradeable, IComposableOFTCore {
    
    /**
     * @notice Approves the presale contract an amount
     * @dev amount the amount to be approved
     */
    function mintToPresaleContract(uint amount) external returns (bool);
    /**
     * @notice Burns the presale contract excess amount
     * @dev amount the amount to be approved
     */
    function burnToPresaleContract(uint amount) external returns (bool);
    
    function setTrustedRemote(uint16 _srcChainId, bytes calldata _path) external;
  
}
