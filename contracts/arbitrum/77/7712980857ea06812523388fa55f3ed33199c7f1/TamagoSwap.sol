// SPDX-License-Identifier: GPL-3.0
//author: Johnleouf21
pragma solidity 0.8.19;

import "./ERC721Holder.sol";
import "./ERC1155Holder.sol";
import "./IERC721.sol";
import "./IERC20.sol";
import "./IERC1155.sol";
import "./Ownable.sol";

/**
* @title This is the contract which added erc1155 into the previous swap contract.
*/
contract TamagoSwap is Ownable, ERC721Holder, ERC1155Holder {

  uint64 private _swapsCounter;
  uint64[] private swapIDs;
  uint96 public etherLocked;
  uint96 public fee;

  address private constant _ZEROADDRESS = address(0);

  mapping (uint64 => Swap) private _swaps;

  struct Swap {
    address payable initiator;
    uint96 initiatorEtherValue;
    address initiatorErc20Address;
    uint256 initiatorErc20Amount;
    address[] initiatorNftAddresses;
    uint256[] initiatorNftIds;
    uint128[] initiatorNftAmounts;
    address payable secondUser;
    uint96 secondUserEtherValue;
    address secondUserErc20Address;
    uint256 secondUserErc20Amount;
    address[] secondUserNftAddresses;
    uint256[] secondUserNftIds;
    uint128[] secondUserNftAmounts;
  }

  event SwapExecuted(address indexed from, address indexed to, uint64 indexed swapId);
  event SwapCanceled(address indexed canceledBy, uint64 indexed swapId);
  event SwapCanceledWithSecondUserRevert(uint64 indexed swapId, bytes reason);
  event SwapCanceledBySecondUser(uint64 indexed swapId);
  event AppFeeChanged(
    uint96 fee
  );
  event TransferEthToSecondUserFailed(uint64 indexed swapId);

  modifier onlyInitiator(uint64 swapId) {
    require(msg.sender == _swaps[swapId].initiator,
      "TamagoSwap: caller is not swap initiator");
    _;
  }

  modifier onlyThisContractItself() {
    require(msg.sender == address(this), "Invalid caller");
    _;
  }

  modifier requireSameLength(address[] memory nftAddresses, uint256[] memory nftIds, uint128[] memory nftAmounts) {
    require(nftAddresses.length == nftIds.length, "TamagoSwap: NFT and ID arrays have to be same length");
    require(nftAddresses.length == nftAmounts.length, "TamagoSwap: NFT and AMOUNT arrays have to be same length");
    _;
  }

  modifier chargeAppFee() {
    require(msg.value >= fee, "TamagoSwap: Sent ETH amount needs to be more or equal application fee");
    _;
  }

  constructor(uint96 initialAppFee, address contractOwnerAddress) {
    fee = initialAppFee;
    super.transferOwnership(contractOwnerAddress);
  }

  function setAppFee(uint96 newFee) external onlyOwner {
    fee = newFee;
    emit AppFeeChanged(newFee);
  }

  function getSwapIDs() public view returns(uint64[] memory){ 
    return swapIDs;
  }

	function getSwap(uint64 swapId) public  view returns (Swap memory)  {
		require((_swaps[swapId].secondUser == msg.sender) || (_swaps[swapId].initiator) == msg.sender, "TamagoSwap: caller is not swap participator");
      return _swaps[swapId];     
  }

  /**
  * @dev First user proposes a swap to the second user with the NFTs that he deposits and wants to trade.
  *      Proposed NFTs are transfered to the TamagoSwap contract and
  *      kept there until the swap is accepted or canceled/rejected.
  *
  * @param secondUser address of the user that the first user wants to trade NFTs with
  * @param nftAddresses array of NFT addressed that want to be traded
  * @param nftIds array of IDs belonging to NFTs that want to be traded
  * @param nftAmounts array of NFT amounts that want to be traded. If the amount is zero, that means 
  * the token is ERC721 token. Otherwise the token is ERC1155 token.
  */
  function proposeSwap(
    address secondUser,
    address[] memory nftAddresses,
    uint256[] memory nftIds,
    uint128[] memory nftAmounts,
    address erc20Address,
    uint256 erc20Amount
  ) external payable chargeAppFee requireSameLength(nftAddresses, nftIds, nftAmounts) {
    uint64 swapsCounter = _swapsCounter + 1;
    _swapsCounter = swapsCounter;
    swapIDs.push(swapsCounter);

    Swap storage swap = _swaps[swapsCounter];
    swap.initiator = payable(msg.sender);

    if(nftAddresses.length > 0) {
      for (uint256 i = 0; i < nftIds.length; i++){
        safeTransferFrom(msg.sender, address(this), nftAddresses[i], nftIds[i], nftAmounts[i], "");
      }

      swap.initiatorNftAddresses = nftAddresses;
      swap.initiatorNftIds = nftIds;
      swap.initiatorNftAmounts = nftAmounts;
    }

    uint96 _fee = fee;
    uint96 initiatorEtherValue;

    if (erc20Address != address(0) && erc20Amount > 0) {
    IERC20 token = IERC20(erc20Address);
    require(token.transferFrom(msg.sender, address(this), erc20Amount), "ERC20 transfer failed");
    swap.initiatorErc20Address = erc20Address;
    swap.initiatorErc20Amount = erc20Amount;
  }

    if (msg.value > _fee) {
      initiatorEtherValue = uint96(msg.value) - _fee;
      swap.initiatorEtherValue = initiatorEtherValue;
      etherLocked += initiatorEtherValue;
    }
    swap.secondUser = payable(secondUser);
  }

  function initiateSwap(
    uint64 swapId,
    address[] memory nftAddresses,
    uint256[] memory nftIds,
    uint128[] memory nftAmounts,
    address erc20Address,
    uint256 erc20Amount
  ) external payable chargeAppFee requireSameLength(nftAddresses, nftIds, nftAmounts) {
    require(_swaps[swapId].secondUser == msg.sender, "TamagoSwap: caller is not swap participator");
    require(
      _swaps[swapId].secondUserEtherValue == 0 &&
      _swaps[swapId].secondUserNftAddresses.length == 0
      , "TamagoSwap: swap already initiated"
    );

    if (nftAddresses.length > 0) {
      for (uint256 i = 0; i < nftIds.length; i++){
        safeTransferFrom(msg.sender, address(this), nftAddresses[i], nftIds[i], nftAmounts[i], "");
      }

      _swaps[swapId].secondUserNftAddresses = nftAddresses;
      _swaps[swapId].secondUserNftIds = nftIds;
      _swaps[swapId].secondUserNftAmounts = nftAmounts;
    }

    uint96 _fee = fee;
    uint96 secondUserEtherValue;

    if (erc20Address != address(0) && erc20Amount > 0) {
    IERC20 token = IERC20(erc20Address);
    require(token.transferFrom(msg.sender, address(this), erc20Amount), "ERC20 transfer failed");
    _swaps[swapId].secondUserErc20Address = erc20Address;
    _swaps[swapId].secondUserErc20Amount = erc20Amount;
  }

    if (msg.value > _fee) {
      secondUserEtherValue = uint96(msg.value) - _fee;
      _swaps[swapId].secondUserEtherValue = secondUserEtherValue;
      etherLocked += secondUserEtherValue;
    }
  }

  function acceptSwap(uint64 swapId) external onlyInitiator(swapId) {
    Swap memory swap = _swaps[swapId];
    
    require(
      (swap.secondUserNftAddresses.length > 0 || swap.secondUserEtherValue > 0) &&
      (swap.initiatorNftAddresses.length > 0 || swap.initiatorEtherValue > 0),
      "TamagoSwap: Can't accept swap, both participants didn't add NFTs"
    );
    
    if (swap.secondUserNftAddresses.length > 0) {
      // transfer NFTs from escrow to initiator
      for (uint256 i = 0; i < swap.secondUserNftIds.length; i++) {
        safeTransferFrom(
          address(this),
          swap.initiator,
          swap.secondUserNftAddresses[i],
          swap.secondUserNftIds[i],
          swap.secondUserNftAmounts[i],
          ""
        );
      }
    }

    if (swap.initiatorNftAddresses.length > 0) {
      // transfer NFTs from escrow to second user
      for (uint256 i = 0; i < swap.initiatorNftIds.length; i++) {
        safeTransferFrom(
          address(this),
          swap.secondUser,
          swap.initiatorNftAddresses[i],
          swap.initiatorNftIds[i],
          swap.initiatorNftAmounts[i],
          ""
        );
      }
    }

    if (swap.initiatorEtherValue > 0) {
      etherLocked -= swap.initiatorEtherValue;
      (bool success,) = swap.secondUser.call{value: swap.initiatorEtherValue}("");
      require(success, "Failed to send Ether to the second user");
    }
    if (swap.secondUserEtherValue > 0) {
      etherLocked -= swap.secondUserEtherValue;
      (bool success,) = swap.initiator.call{value: swap.secondUserEtherValue}("");
      require(success, "Failed to send Ether to the initiator user");
    }
    if (swap.secondUserErc20Amount > 0) {
      // Transfer ERC20 tokens from escrow to initiator
      IERC20 token = IERC20(swap.secondUserErc20Address);
      require(token.transfer(swap.initiator, swap.secondUserErc20Amount), "ERC20 transfer failed");
    }

    if (swap.initiatorErc20Amount > 0) {
      // Transfer ERC20 tokens from escrow to second user
      IERC20 token = IERC20(swap.initiatorErc20Address);
      require(token.transfer(swap.secondUser, swap.initiatorErc20Amount), "ERC20 transfer failed");
    }

    emit SwapExecuted(swap.initiator, swap.secondUser, swapId);
    
    delete _swaps[swapId];
    deleteArrayEntry(swapId);
  }

  function cancelSwap(uint64 swapId) external returns (bool) {
    Swap memory swap = _swaps[swapId];
     

    require(
      swap.initiator == msg.sender || swap.secondUser == msg.sender,
      "TamagoSwap: Can't cancel swap, must be swap participant"
    );

    if (swap.initiatorNftAddresses.length > 0) {
      // return initiator NFTs
      for (uint256 i = 0; i < swap.initiatorNftIds.length; i++) {
        safeTransferFrom(
          address(this),
          swap.initiator,
          swap.initiatorNftAddresses[i],
          swap.initiatorNftIds[i],
          swap.initiatorNftAmounts[i],
          ""
        );
      }
    }

    if (swap.initiatorEtherValue != 0) {
      etherLocked -= swap.initiatorEtherValue;
      (bool success,) = swap.initiator.call{value: swap.initiatorEtherValue}("");
      require(success, "Failed to send Ether to the initiator user");
    }

    if(swap.secondUserNftAddresses.length > 0) {
      // return second user NFTs
      try this.safeMultipleTransfersFrom(
        address(this),
        swap.secondUser,
        swap.secondUserNftAddresses,
        swap.secondUserNftIds,
        swap.secondUserNftAmounts
      ) {} catch (bytes memory reason) {
        _swaps[swapId].secondUser = swap.secondUser;
        _swaps[swapId].secondUserNftAddresses = swap.secondUserNftAddresses;
        _swaps[swapId].secondUserNftIds = swap.secondUserNftIds;
        _swaps[swapId].secondUserNftAmounts = swap.secondUserNftAmounts;
        _swaps[swapId].secondUserEtherValue = swap.secondUserEtherValue;
        emit SwapCanceledWithSecondUserRevert(swapId, reason);
        return true;
      }
    }

    if (swap.secondUserEtherValue != 0) {
      etherLocked -= swap.secondUserEtherValue;
      (bool success,) = swap.secondUser.call{value: swap.secondUserEtherValue}("");
      if (!success) {
        etherLocked += swap.secondUserEtherValue;
        _swaps[swapId].secondUser = swap.secondUser;
        _swaps[swapId].secondUserEtherValue = swap.secondUserEtherValue;
        emit TransferEthToSecondUserFailed(swapId);
        return true;
      }
    }

    if (swap.initiatorErc20Amount > 0) {
      // Return initiator's ERC20 tokens
      IERC20 token = IERC20(swap.initiatorErc20Address);
      require(token.transfer(swap.initiator, swap.initiatorErc20Amount), "ERC20 transfer failed");
    }

    if (swap.secondUserErc20Amount > 0) {
      // Return second user's ERC20 tokens
      IERC20 token = IERC20(swap.secondUserErc20Address);
      require(token.transfer(swap.secondUser, swap.secondUserErc20Amount), "ERC20 transfer failed");
    }

    emit SwapCanceled(msg.sender, swapId);
    delete _swaps[swapId];
    deleteArrayEntry(swapId);
    return true;
	
  }

  function deleteArrayEntry(uint64 swapId) public {
        uint index = findSwapIdIndex(swapId);
        if (index != uint64(int64(-1))) {
            uint64[] memory newSwapIDs = new uint64[](swapIDs.length - 1);
            for (uint i = 0; i < index; i++) {
                newSwapIDs[i] = swapIDs[i];
            }
            for (uint i = index + 1; i < swapIDs.length; i++) {
                newSwapIDs[i - 1] = swapIDs[i];
            }
            swapIDs = newSwapIDs;
        }
    }

    function findSwapIdIndex(uint64 swapId) private view returns (uint64) {
    for (uint64 i = 0; i < swapIDs.length; i++) {
        if (swapIDs[i] == swapId) {
            return i;
        }
    }
    return uint64(int64(-1));
}

  function safeMultipleTransfersFrom(
    address from,
    address to,
    address[] memory nftAddresses,
    uint256[] memory nftIds,
    uint128[] memory nftAmounts
  ) external onlyThisContractItself {
    for (uint256 i = 0; i < nftIds.length; i++) {
      safeTransferFrom(from, to, nftAddresses[i], nftIds[i], nftAmounts[i], "");
    }
  }

  function safeTransferFrom(
    address from,
    address to,
    address tokenAddress,
    uint256 tokenId,
    uint256 tokenAmount,
    bytes memory _data
  ) internal virtual {
    if (tokenAmount == 0) {
      IERC721(tokenAddress).transferFrom(from, to, tokenId);
    } else {
      IERC1155(tokenAddress).safeTransferFrom(from, to, tokenId, tokenAmount, _data);
    }
  }

  function withdrawEther(address payable recipient) external onlyOwner {
    require(recipient != address(0), "TamagoSwap: transfer to the zero address");
    recipient.transfer((address(this).balance - etherLocked));
  }

  function getBalance() public view onlyOwner returns (uint256) {
    return (address(this).balance - etherLocked);
  }
}
