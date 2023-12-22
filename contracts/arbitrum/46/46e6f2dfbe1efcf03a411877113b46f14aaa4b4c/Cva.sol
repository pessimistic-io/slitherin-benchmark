// SPDX-License-Identifier: MIT

pragma solidity 0.8.13;

import "./ERC165.sol";
import "./IERC20.sol";
import "./Pausable.sol";
import "./SafeERC20.sol";

import "./ICvaFactory.sol";
import "./ICva.sol";
import "./IBridge.sol";
import "./IHandler.sol";
import "./IWETH.sol";

/**
 * Contract that will forward any incoming Ether to the creator of the contract
 *
 */
contract Cva is ERC165, ICva, Pausable {
  address public constant NATIVE_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
  bytes32 public constant WITHDRAWER_ROLE = keccak256('WITHDRAWER_ROLE');

  bool public isInitialized;
  bytes public userDID;

  address public wethAddress;
  address public factoryAddress;

  /**
   * Initialize the contract, and sets the config
   */
  function init(bytes calldata _userDID, address _wethAddress) external {
    require(!isInitialized, 'initialized');
    isInitialized = true;

    userDID = _userDID;
    wethAddress = _wethAddress;
    factoryAddress = _msgSender();

    // one-time WETH approve
    _approve(_wethAddress);
  }

  modifier onlyRelayer() {
    require(_msgSender() == ICvaFactory(factoryAddress).relayerAddress(), 'relayer only');
    _;
  }

  modifier onlyOwner() {
    require(_msgSender() == ICvaFactory(factoryAddress).owner(), 'owner only');
    _;
  }

  modifier onlyWithdrawer() {
    require(ICvaFactory(factoryAddress).hasRole(WITHDRAWER_ROLE, _msgSender()), 'withdrawer only');
    _;
  }

  modifier onlyValid() {
    require(ICvaFactory(factoryAddress).isValid(), '!valid');
    _;
  }

  function supportsInterface(bytes4 _interfaceID) public view override returns (bool) {
    return _interfaceID == type(ICva).interfaceId || super.supportsInterface(_interfaceID);
  }

  // one-time approve
  function _approve(address _tokenAddress) internal {
    SafeERC20.safeApprove(IERC20(_tokenAddress), ICvaFactory(factoryAddress).handlerAddress(), type(uint256).max);
  }

  // deposit to bridge
  function _deposit(
    uint8 _destinationDomainID,
    bytes32 _resourceID,
    bytes memory _depositData,
    bytes memory _feeData
  ) internal {
    IBridge(ICvaFactory(factoryAddress).bridgeAddress()).deposit(
      _destinationDomainID,
      _resourceID,
      _depositData,
      _feeData
    );
  }

  // Used only once at 1st deposit, when Non-ETH (ERC20) is already transferred before/at VA created
  function approveAndDeposit(
    address _tokenAddress,
    uint8 _destinationDomainID,
    bytes32 _resourceID,
    bytes memory _depositData,
    bytes memory _feeData
  ) external onlyRelayer onlyValid whenNotPaused {
    // one-time approve
    _approve(_tokenAddress);

    // deposit to bridge
    _deposit(_destinationDomainID, _resourceID, _depositData, _feeData);
  }

  // used only at 2nd deposit and so on
  function deposit(
    uint8 _destinationDomainID,
    bytes32 _resourceID,
    bytes memory _depositData,
    bytes memory _feeData
  ) external onlyRelayer onlyValid whenNotPaused {
    if (
      IHandler(ICvaFactory(factoryAddress).handlerAddress())._resourceIDToTokenContractAddress(_resourceID) ==
      NATIVE_ADDRESS
    ) {
      (, , uint256 ethBal) = decodeDepositData(_depositData);

      require(address(this).balance >= ethBal, '!balance');

      // wrap native
      IWETH(wethAddress).deposit{value: ethBal}();
    }

    // deposit to bridge
    _deposit(_destinationDomainID, _resourceID, _depositData, _feeData);
  }

  function emergencyTokenWithdraw(address _token, address _to, uint256 _value) external onlyWithdrawer whenPaused {
    // get token balance
    uint256 tokenBalance = IERC20(_token).balanceOf(address(this));

    // adjust
    if (_value > tokenBalance) _value = tokenBalance;

    // move funds
    SafeERC20.safeTransfer(IERC20(_token), _to, _value);
  }

  function emergencyNativeWithdraw(address _to, uint256 _value) external onlyWithdrawer whenPaused {
    // get native balance
    uint256 nativeBalance = address(this).balance;

    // adjust
    if (_value > nativeBalance) _value = nativeBalance;

    // move funds
    (bool isSuccess, ) = _to.call{value: _value}('');
    require(isSuccess, 'failed');
  }

  function setFactory(address _factoryAddress) external onlyOwner whenPaused {
    factoryAddress = _factoryAddress;
  }

  function togglePause() external onlyOwner {
    if (paused()) {
      _unpause();
    } else {
      _pause();
    }
  }

  function decodeDepositData(
    bytes memory _depositData
  ) internal pure returns (address sender, uint8 srcTokenDecimals, uint256 amount) {
    (sender, srcTokenDecimals, amount) = abi.decode(_depositData, (address, uint8, uint256));
  }

  receive() external payable onlyValid {
    // emit native received event
    ICvaFactory(factoryAddress).emitNativeReceived(_msgSender(), address(this), msg.value);
  }

  fallback() external payable onlyValid {
    // emit native received event
    ICvaFactory(factoryAddress).emitNativeReceived(_msgSender(), address(this), msg.value);
  }
}

