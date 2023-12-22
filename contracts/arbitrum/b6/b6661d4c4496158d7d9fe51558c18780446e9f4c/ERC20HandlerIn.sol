// SPDX-License-Identifier: MIT

pragma solidity ^0.8.13;

import "./Initializable.sol";
import "./UUPSUpgradeable.sol";
import "./HandlerHelpersCustom.sol";
import "./ERC20Safe.sol";
import "./AdminProxyManager.sol";
import "./IDepositExecute.sol";
import "./IWETH.sol";

/**
    @title Handles ERC20 deposits and deposit executions.
    @author ChainSafe Systems.
    @notice This contract is intended to be used with the Bridge contract.
 */
contract ERC20HandlerIn is
  Initializable,
  UUPSUpgradeable,
  AdminProxyManager,
  IDepositExecute,
  HandlerHelpersCustom,
  ERC20Safe
{
  // native address contract
  address public constant NATIVE_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

  // WETH contract address
  IWETH public _WETH;

  /**
    @param bridgeAddress Contract address of previously deployed Bridge.
  */
  function init(address bridgeAddress, address WETH, address owner, address adminProxy) external initializer proxied {
    require(WETH != address(_WETH), 'bad');

    __UUPSUpgradeable_init();
    __AdminProxyManager_init(adminProxy);
    __HandlerHelpersCustom_init(bridgeAddress, owner);

    _WETH = IWETH(WETH);
  }

  function _authorizeUpgrade(address newImplementation) internal virtual override proxied {}

  /**
    @notice A deposit is initiatied by making a deposit in the Bridge contract.
    @param resourceID ResourceID used to find address of token to be used for deposit.
    @param depositer Address of account making the deposit in the Bridge contract.
    @param data Consists of {amount} padded to 32 bytes.
    @notice Data passed into the function should be constructed as follows:
    amount                      uint256     bytes   0 - 32
    @dev Depending if the corresponding {tokenAddress} for the parsed {resourceID} is
    marked true in {_burnList}, deposited tokens will be burned, if not, they will be locked.
    @return an empty data.
  */
  function deposit(
    bytes32 resourceID,
    address depositer,
    bytes memory data
  ) external virtual override returns (bytes memory) {
    _onlyBridge();

    // Data decoder begin
    address sender; // cVa
    uint8 srcTokenDecimals; // src token decimal
    uint256 amount;

    (sender, srcTokenDecimals, amount) = abi.decode(data, (address, uint8, uint256));
    // Data decoder end

    address tokenAddress = _resourceIDToTokenContractAddress[resourceID];
    require(_contractWhitelist[tokenAddress], 'provided tokenAddress is not whitelisted');

    if (tokenAddress == NATIVE_ADDRESS) {
      lockERC20(address(_WETH), depositer, address(this), amount);
    } else {
      lockERC20(tokenAddress, depositer, address(this), amount);
    }
  }

  /**
    @notice Proposal execution should be initiated when a proposal is finalized in the Bridge contract.
    by a relayer on the deposit's destination chain.
    @param data Consists of {resourceID}, {amount}, {lenDestinationRecipientAddress},
    and {destinationRecipientAddress} all padded to 32 bytes.
    @notice Data passed into the function should be constructed as follows:
    amount                                 uint256     bytes  0 - 32
    destinationRecipientAddress length     uint256     bytes  32 - 64
    destinationRecipientAddress            bytes       bytes  64 - END
  */
  function executeProposal(bytes32 resourceID, bytes calldata data) external virtual override {
    _onlyBridge();

    // Data decoder begin
    address recipient;
    uint8 srcTokenDecimals; // src token decimal
    uint256 amount;
    bool isWrapped;

    (recipient, srcTokenDecimals, amount, isWrapped) = abi.decode(data, (address, uint8, uint256, bool));
    // Data decoder end

    address tokenAddress = _resourceIDToTokenContractAddress[resourceID];
    require(recipient != address(0) && _contractWhitelist[tokenAddress], 'bad');

    // adjust token decimal
    uint8 token_decimal;
    if (tokenAddress == NATIVE_ADDRESS) {
      token_decimal = 18;
    } else {
      token_decimal = IERC20Metadata(tokenAddress).decimals();
    }

    amount = (amount * 10 ** token_decimal) / 10 ** srcTokenDecimals;

    // How to release
    // 1. Token native true, isWrapped false => send as native
    // 2. Token native true, isWrapped true => send as wrapped (erc20)
    // 3. Token native false, isWrapped false => send as erc20
    // 4. Token native false, isWrapped true => send as erc20

    if (tokenAddress == NATIVE_ADDRESS && !isWrapped) {
      _WETH.withdraw(amount);
      (bool success, ) = recipient.call{value: amount}('');
      require(success, 'fail wd eth');
    } else if (tokenAddress == NATIVE_ADDRESS && isWrapped) {
      releaseERC20(address(_WETH), recipient, amount);
    } else {
      releaseERC20(tokenAddress, recipient, amount);
    }
  }

  /**
    @notice Used to manually release ERC20 tokens from ERC20Safe.
    @param data Consists of {tokenAddress}, {recipient}, and {amount} all padded to 32 bytes.
    @notice Data passed into the function should be constructed as follows:
    tokenAddress                           address     bytes  0 - 32
    recipient                              address     bytes  32 - 64
    amount                                 uint        bytes  64 - 96
  */
  function withdraw(bytes memory data) external virtual override {
    _onlyBridge();

    address tokenAddress;
    address recipient;
    uint amount;

    (tokenAddress, recipient, amount) = abi.decode(data, (address, address, uint));

    releaseERC20(tokenAddress, recipient, amount);
  }

  function setWETH(address WETH) external virtual onlyOwner {
    require(WETH != address(_WETH), 'bad');
    _WETH = IWETH(WETH);
  }

  receive() external payable virtual {}
}

