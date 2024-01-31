// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;
import "./IInventory.sol";
import "./Initializable.sol";
import "./UUPSUpgradeable.sol";

import "./LibIMPT.sol";

contract Inventory is IInventory, Initializable, UUPSUpgradeable {
  address public override stableWallet;

  // Mapping tokenID to storage values in struct
  mapping(uint256 => TokenDetails) public tokenDetails;

  CarbonCreditNFT public override nftContract;
  IAccessManager public override AccessManager;

  /// @dev modifies function so that it is only callable by the stable wallet
  modifier onlyStableWallet() {
    if (msg.sender != stableWallet) {
      revert UnauthorizedCall();
    }
    _;
  }

  /// @dev modifies function so that it is only callable by the Carbon Credit NFT contract
  modifier onlyNftContract() {
    if (msg.sender != address(nftContract)) {
      revert UnauthorizedCall();
    }
    _;
  }

  /// @dev modifies a function so that it is only callable by a user with the correct roles
  modifier onlyIMPTRole(bytes32 _role, IAccessManager _AccessManager) {
    LibIMPT._hasIMPTRole(_role, msg.sender, AccessManager);
    _;
  }

  function initialize(
    InventoryConstructorParams memory _params
  ) external initializer {
    LibIMPT._checkZeroAddress(_params.stableWallet);
    LibIMPT._checkZeroAddress(address(_params.nftContract));
    LibIMPT._checkZeroAddress(address(_params.AccessManager));
    __UUPSUpgradeable_init();

    AccessManager = _params.AccessManager;

    stableWallet = _params.stableWallet;
    nftContract = _params.nftContract;
  }

  function setStableWallet(
    address _stableWallet
  ) external override onlyIMPTRole(LibIMPT.IMPT_ADMIN_ROLE, AccessManager) {
    LibIMPT._checkZeroAddress(_stableWallet);
    stableWallet = _stableWallet;
    emit UpdateWallet(_stableWallet);
  }

  function setNftContract(
    CarbonCreditNFT _nftContract
  ) external override onlyIMPTRole(LibIMPT.IMPT_ADMIN_ROLE, AccessManager) {
    LibIMPT._checkZeroAddress(address(_nftContract));
    nftContract = _nftContract;
  }

  /// @dev This function is to check that the upgrade functions in UUPSUpgradeable are being called by an address with the correct role
  function _authorizeUpgrade(
    address newImplementation
  ) internal override onlyIMPTRole(LibIMPT.IMPT_ADMIN_ROLE, AccessManager) {}

  function updateTotalMinted(
    uint256 _tokenId,
    uint256 _amount
  ) external override onlyNftContract {
    TokenDetails memory token = tokenDetails[_tokenId];
    if (
      _amount > token.totalSupply - (token.tokensMinted + token.imptBurnCount)
    ) {
      revert NotEnoughSupply();
    }
    tokenDetails[_tokenId].tokensMinted += _amount;
    emit TotalSupplyUpdated(_tokenId, _amount);
  }

  function updateTotalSupply(
    uint256 _tokenId,
    uint256 _amount
  ) public override onlyStableWallet {
    tokenDetails[_tokenId].totalSupply = _amount;
    emit TotalSupplyUpdated(_tokenId, _amount);
  }

  function updateBulkTotalSupply(
    uint256[] memory _tokenIds,
    uint256[] memory _amounts
  ) public override onlyStableWallet {
    // NOTE: Gas usage on this function is less than calling above function x times (see unit tests)
    for (uint16 i; i < _tokenIds.length; i++) {
      updateTotalSupply(_tokenIds[i], _amounts[i]);
    }
  }

  function getAllTokenDetails(
    uint256[] memory _tokenIds
  ) external view override returns (TokenDetails[] memory _tokenDetails) {
    TokenDetails[] memory supplies = new TokenDetails[](_tokenIds.length);
    for (uint16 i; i < _tokenIds.length; i++) {
      supplies[i] = tokenDetails[_tokenIds[i]];
    }
    return supplies;
  }

  function incrementBurnCount(
    uint256 _tokenId,
    uint256 _amount
  ) external override onlyNftContract {
    TokenDetails storage newTokenDetail = tokenDetails[_tokenId];
    newTokenDetail.imptBurnCount += _amount;
    newTokenDetail.tokensMinted -= _amount;
    tokenDetails[_tokenId] = newTokenDetail;
    emit BurnCountUpdated(_tokenId, _amount);
  }

  function confirmBurnCounts(
    uint256 _tokenId,
    uint256 _amount
  ) public override onlyStableWallet {
    uint256 retireCount = tokenDetails[_tokenId].imptBurnCount;
    if (retireCount == 0) {
      revert AmountMustBeMoreThanZero();
    }
    if (_amount == 0) {
      revert AmountMustBeMoreThanZero();
    }
    tokenDetails[_tokenId].imptBurnCount -= _amount;
    emit BurnSent(_tokenId, _amount);
  }

  function bulkConfirmBurnCounts(
    uint256[] memory _tokenIds,
    uint256[] memory _amounts
  ) public override onlyStableWallet {
    for (uint16 i; i < _tokenIds.length; i++) {
      confirmBurnCounts(_tokenIds[i], _amounts[i]);
    }
  }

  function confirmAndUpdate(
    uint256 _tokenId,
    uint256 _newTotalSupply,
    uint256 _confirmedBurned
  ) public override onlyStableWallet {
    confirmBurnCounts(_tokenId, _confirmedBurned);
    updateTotalSupply(_tokenId, _newTotalSupply);
  }

  function bulkConfirmAndUpdate(
    uint256[] memory _tokenIds,
    uint256[] memory _newTotalSupplies,
    uint256[] memory _confirmedBurnAmount
  ) public override onlyStableWallet {
    bulkConfirmBurnCounts(_tokenIds, _confirmedBurnAmount);
    updateBulkTotalSupply(_tokenIds, _newTotalSupplies);
  }
}

