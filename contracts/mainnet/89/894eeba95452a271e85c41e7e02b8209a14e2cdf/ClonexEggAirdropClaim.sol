// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.4;

import "./Ownable.sol";
import "./IERC721.sol";
import "./IERC721Receiver.sol";

import "./INFTStrategy.sol";

interface IEgg is IERC721 {
    function mint(uint256[] calldata _ids) external;
}

contract ClonexEggAirdropClaim is Ownable, INFTStrategy, IERC721Receiver {
    error NotImplemented();
    error Unauthorized();

    IERC721 public constant CLONEX = IERC721(0x49cF6f5d44E70224e2E23fDcdd2C053F30aDA28B);
    IEgg public constant EGG = IEgg(0x6c410cF0B8c113Dc6A7641b431390B11d5515082);

    address private currentLoanee;

    function kind() external pure override returns (Kind) {
        return Kind.FLASH;
    }

    function depositAddress(address) external view override returns (address) {
        return address(this);
    }

    /// @dev Can only be called by the owner. 
    /// Claims the EGG airdrop using `_nftIndexes` and sends it to `_owner`.
    function afterDeposit(address _owner, uint256[] calldata _nftIndexes, bytes calldata) external override onlyOwner {
        currentLoanee = _owner;

        EGG.mint(_nftIndexes);
        
        for (uint256 i; i < _nftIndexes.length; i++) {
            CLONEX.transferFrom(address(this), msg.sender, _nftIndexes[i]);
        }

        delete currentLoanee;
    }

    /// @dev Not implemented for FLASH strategies
    function withdraw(address, address, uint256) external pure override {
        revert NotImplemented();
    }

    /// @dev Can only be called by `EGG`.
    /// Transfers `_tokenId` to `currentLoanee`
    function onERC721Received(
        address,
        address,
        uint256 _tokenId,
        bytes calldata
    ) external override returns (bytes4) {
        if (msg.sender != address(EGG)) {
            revert Unauthorized();
        }

        EGG.transferFrom(address(this), currentLoanee, _tokenId);

        return IERC721Receiver.onERC721Received.selector;
    }
}
