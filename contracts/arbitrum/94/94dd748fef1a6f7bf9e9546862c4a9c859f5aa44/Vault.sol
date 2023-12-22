// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import {IERC20} from "./IERC20.sol";
import {SafeERC20} from "./SafeERC20.sol";
import {ERC721} from "./ERC721.sol";
import {ERC721Enumerable} from "./ERC721Enumerable.sol";
import {IERC165} from "./IERC165.sol";

import {IVault} from "./IVault.sol";
import {IDefii} from "./IDefii.sol";
import {OperatorMixin} from "./OperatorMixin.sol";

contract Vault is ERC721, ERC721Enumerable, OperatorMixin, IVault {
    using SafeERC20 for IERC20;

    uint256 nextTokenId;

    address public immutable notion;

    mapping(uint256 nft => mapping(address ft => uint256 balance)) public funds;
    mapping(uint256 nft => mapping(address defii => uint256 amount))
        public notionInDefii;

    mapping(address => bool) defiis;
    address[] allDefiis;

    constructor(
        address notion_,
        address[] memory defiis_,
        string memory vaultName,
        string memory vaultSymbol
    )
        ERC721(vaultName, vaultSymbol)
        OperatorMixin(abi.encodePacked("Operator for", vaultName))
    {
        notion = notion_;

        allDefiis = defiis_;
        for (uint256 i = 0; i < defiis_.length; i++) {
            defiis[defiis_[i]] = true;
        }
    }

    function deposit(uint256 amount) external {
        uint256 tokenId = _getTokenId(msg.sender, true);

        IERC20(notion).safeTransferFrom(msg.sender, address(this), amount);
        funds[tokenId][notion] += amount;
        emit FundsDeposited(msg.sender, amount);
    }

    function startWithdraw(uint256 percentage) external {
        uint256 tokenId = _getTokenId(msg.sender, false);
        emit WithdrawStarted(tokenId, percentage);
    }

    function enterDefii(
        address defii,
        uint256 tokenId,
        uint256 amount,
        IDefii.Instruction[] calldata instructions
    ) external payable operatorCheckApproval(ownerOf(tokenId)) {
        if (!defiis[defii]) {
            revert UnsupportedDefii(defii);
        }

        funds[tokenId][notion] -= amount;
        IERC20(notion).safeIncreaseAllowance(defii, amount);
        IDefii(defii).enter{value: msg.value}(
            notion,
            amount,
            tokenId,
            instructions
        );
    }

    function exitDefii(
        address defii,
        uint256 tokenId,
        uint256 percentage, // bps
        IDefii.Instruction[] calldata instructions
    ) external payable operatorCheckApproval(ownerOf(tokenId)) {
        if (!defiis[defii]) {
            revert UnsupportedDefii(defii);
        }

        uint256 lpAmount = (funds[tokenId][defii] * percentage) / 1e4;

        funds[tokenId][defii] -= lpAmount;
        IDefii(defii).exit{value: msg.value}(
            lpAmount,
            notion,
            tokenId,
            instructions
        );
    }

    function collectFunds(
        address,
        uint256 id,
        address token,
        uint256 amount
    ) external {
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        funds[id][token] += amount;
    }

    function _getTokenId(address user, bool mint) internal returns (uint256) {
        if (balanceOf(user) == 0 && mint) {
            uint256 tokenId = nextTokenId++;
            _mint(user, tokenId);
            return tokenId;
        }
        return tokenOfOwnerByIndex(user, 0);
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId,
        uint256 batchSize
    ) internal override(ERC721, ERC721Enumerable) {
        super._beforeTokenTransfer(from, to, tokenId, batchSize);
    }

    function supportsInterface(
        bytes4 interfaceId
    ) public view override(IERC165, ERC721, ERC721Enumerable) returns (bool) {
        return super.supportsInterface(interfaceId);
    }
}

