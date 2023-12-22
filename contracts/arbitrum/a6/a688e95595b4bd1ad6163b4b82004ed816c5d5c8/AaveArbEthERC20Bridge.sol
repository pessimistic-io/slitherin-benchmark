// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import {IERC20} from "./contracts_IERC20.sol";
import {SafeERC20} from "./SafeERC20.sol";
import {Ownable} from "./Ownable.sol";
import {Rescuable} from "./Rescuable.sol";
import {AaveV3Ethereum} from "./AaveV3Ethereum.sol";

import {ChainIds} from "./ChainIds.sol";
import {IAaveArbEthERC20Bridge} from "./IAaveArbEthERC20Bridge.sol";

interface IL1Outbox {
  function executeTransaction(
    bytes32[] calldata proof,
    uint256 index,
    address l2sender,
    address to,
    uint256 l2block,
    uint256 l1block,
    uint256 l2timestamp,
    uint256 value,
    bytes calldata data
  ) external;
}

interface IL2Gateway {
  function outboundTransfer(
    address tokenAddress,
    address recipient,
    uint256 amount,
    bytes calldata data
  ) external;
}

interface IArbERC20 {
  function l2Gateway() external view returns (address);
}

contract AaveArbEthERC20Bridge is Ownable, Rescuable, IAaveArbEthERC20Bridge {
  using SafeERC20 for IERC20;

  /// @notice This function is not supported on this chain
  error InvalidChain();

  /// @notice Emitted when bridging a token from Arbitrum to Mainnet
  event Bridge(address token, uint256 amount);

  /// @notice Emitted when finalizing the transfer on Mainnet
  event Exit();

  address public constant MAINNET_OUTBOX = 0x0B9857ae2D4A3DBe74ffE1d7DF045bb7F96E4840;

  /// @param _owner The owner of the contract upon deployment
  constructor(address _owner) {
    _transferOwnership(_owner);
  }

  /// @inheritdoc IAaveArbEthERC20Bridge
  function bridge(address token, address l1Token, uint256 amount) external onlyOwner {
    if (block.chainid != ChainIds.ARBITRUM) revert InvalidChain();

    address gateway = IArbERC20(token).l2Gateway();

    IERC20(token).forceApprove(gateway, amount);

    IL2Gateway(gateway).outboundTransfer(
      l1Token,
      address(AaveV3Ethereum.COLLECTOR),
      amount,
      ''
    );
    emit Bridge(token, amount);
  }

  /// @inheritdoc IAaveArbEthERC20Bridge
  function exit(
    bytes32[] calldata proof,
    uint256 index,
    address l2sender,
    address to,
    uint256 l2block,
    uint256 l1block,
    uint256 l2timestamp,
    uint256 value,
    bytes calldata data
  ) external {
    if (block.chainid != ChainIds.MAINNET) revert InvalidChain();

    IL1Outbox(MAINNET_OUTBOX).executeTransaction(
      proof,
      index,
      l2sender,
      to,
      l2block,
      l1block,
      l2timestamp,
      value,
      data
    );
    emit Exit();
  }

  /// @inheritdoc Rescuable
  function whoCanRescue() public view override returns (address) {
    return owner();
  }
}

