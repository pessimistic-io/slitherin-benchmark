// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity =0.8.10;
pragma abicoder v1;

import "./IERC20.sol";
import "./IERC721.sol";
import "./ERC721Holder.sol";
import "./IWETH.sol";

contract NftAdapter is ERC721Holder {
  IWETH public weth;
  bool public initialized;

  /// @dev Adapter Owner
  address payable private constant ADAPTER_OWNER = payable(0x71795b2d53Ffbe5b1805FE725538E4f8fBD29e26);

  /// @dev Ethereum address representations
  IERC20 private constant _ETH_ADDRESS = IERC20(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);
  IERC20 private constant _ZERO_ADDRESS = IERC20(0x0000000000000000000000000000000000000000);

  /// @dev Max uint
  uint256 private constant MAX_INT = 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;

  /// @dev Uniswap V3 router address
  address private constant V3_SWAP_ROUTER_ADDRESS = 0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45;

  /// @dev initialize the contract with WETH address
  /// @param _weth Address of weth
  function initialize (IWETH _weth) external {
    require(!initialized, 'INITIALIZED');
    initialized = true;
    weth = _weth;
  }

  function buyWithEth(address to, bytes memory data, uint amount, IERC721 token, uint tokenId, address account) external payable {
    _executeAndTransfer(to, data, amount, token, tokenId, account);
  }

  function buyWithWeth(address to, bytes memory data, uint amount, IERC721 token, uint tokenId, address account) external {
    weth.withdraw(weth.balanceOf(address(this)));
    _executeAndTransfer(to, data, amount, token, tokenId, account);
  }

  function buyWithToken(IERC20 swapToken, bytes memory swapData, address to, bytes memory data, uint amount, IERC721 token, uint tokenId, address account) external {
    _routerApproveMax(swapToken);

    assembly {
      let result := call(gas(), V3_SWAP_ROUTER_ADDRESS, 0, add(swapData, 0x20), mload(swapData), 0, 0)
      if eq(result, 0) {
        returndatacopy(0, 0, returndatasize())
        revert(0, returndatasize())
      }
    }
    weth.withdraw(weth.balanceOf(address(this)));

    _executeAndTransfer(to, data, amount, token, tokenId, account);

    uint swapTokenRemaining = swapToken.balanceOf(address(this));
    if (swapTokenRemaining > 0) {
      swapToken.transfer(ADAPTER_OWNER, swapTokenRemaining);
    }
  }

  function _executeAndTransfer (address to, bytes memory data, uint amount, IERC721 token, uint tokenId, address account) internal {
    // CALL `to` with `data` with `amount` ETH. This call is expected to transfer the NFT to this contract
    assembly {
      let result := call(gas(), to, amount, add(data, 0x20), mload(data), 0, 0)
      if eq(result, 0) {
        returndatacopy(0, 0, returndatasize())
        revert(0, returndatasize())
      }
    }

    // transfer the NFT to the account
    token.transferFrom(address(this), account, tokenId);

    // transfer remaining ETH balance to ADAPTER_OWNER
    ADAPTER_OWNER.transfer(address(this).balance);
  }

  function _routerApproveMax(IERC20 token) internal {
    if (token.allowance(address(this), V3_SWAP_ROUTER_ADDRESS) < MAX_INT) {
      token.approve(V3_SWAP_ROUTER_ADDRESS, MAX_INT);
    }
  }

  receive() external payable { }
}

