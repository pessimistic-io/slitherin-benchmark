// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.4.22 <0.9.0;
import "./Address.sol";
import "./IERC20.sol";
import "./SafeERC20.sol";

contract EvmOppyBridge {
  using Address for address;
  using SafeERC20 for IERC20;

  event OppyTransfer(address from, address to, uint256 amount, address contractAddress, bytes memo);
  
  function oppyTransfer(address toAddress, uint256 amount, address contractAddress, bytes calldata memo) public {
    // require(contractAddress.isContract(), "not a contract address"); // boss suggested to keep this line
    // some ERC20 have not return boolean of transferFrom function, eg: USDT on Ethereum
    IERC20(contractAddress).transferFrom(msg.sender, toAddress, amount);
    emit OppyTransfer(msg.sender, toAddress, amount, contractAddress, memo);
  }
}
