// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.12;

import "./ERC1155Upgradeable.sol";
import "./Initializable.sol";
import "./UUPSUpgradeable.sol";
import "./IERC6372.sol";
import "./SafeCast.sol";
import "./Checkpoints.sol";
import "./IConfig.sol";
import "./IShares.sol";
import "./IVAMM.sol";

contract SharesV2 is
    IERC6372,
    Initializable,
    ERC1155Upgradeable,
    IShares,
    UUPSUpgradeable
{
    using Checkpoints for Checkpoints.Trace224;

    // Record each user's point at each timepoint.
    /// @custom:oz-retyped-from mapping(address => Checkpoints.History)
    mapping(uint256 id => mapping(address => Checkpoints.Trace224))
        private _balanceCheckpoints;

    /// @custom:oz-retyped-from Checkpoints.History
    mapping(uint256 id => Checkpoints.Trace224) private _totalCheckpoints;

    mapping(uint256 id => Checkpoints.Trace224) private _membersCheckpoints;

    mapping(address => bool) private _holder;

    IConfig private _config;

    modifier onlyOwner() {
        address owner = _config.owner();
        require(msg.sender == owner, "Shares: caller is not the owner");
        _;
    }

    modifier onlyVamm() {
        address vamm = _config.getVAMM();
        require(msg.sender == address(vamm), "Shares: caller is not the vamm");
        _;
    }

    function initialize(IConfig config_) public initializer {
        __ERC1155_init("https://metadata.sosotribe.com");
        __UUPSUpgradeable_init();
        _config = config_;
    }

    function registeHolder(address holder) external onlyOwner {
        _holder[holder] = true;
    }

    function deregisteHolder(address holder) external onlyOwner {
        _holder[holder] = false;
    }

    function setURI(string memory newuri) public onlyOwner {
        _setURI(newuri);
    }

    function contractURI() public pure returns (string memory) {
        return "https://sosotribe.com/api/shareContractMetadata";
    }

    /// @dev This event emits when the metadata of a token is changed.
    /// So that the third-party platforms such as NFT market could
    /// timely update the images and related attributes of the NFT.
    event MetadataUpdate(uint256 _tokenId);

    /// @dev This event emits when the metadata of a range of tokens is changed.
    /// So that the third-party platforms such as NFT market could
    /// timely update the images and related attributes of the NFTs.
    event BatchMetadataUpdate(uint256 _fromTokenId, uint256 _toTokenId);

    function metadataUpdate(address shareId) external onlyVamm {
        if (shareId == address(0)) {
            emit BatchMetadataUpdate(0, type(uint256).max);
        }
        uint256 id = convertSharesId(shareId);
        emit MetadataUpdate(id);
    }

    function isApprovedForAll(
        address account,
        address operator
    )
        public
        view
        override(ERC1155Upgradeable, IERC1155Upgradeable)
        returns (bool)
    {
        address sequencer = _config.getSequencer();
        IVAMM vamm = IVAMM(_config.getVAMM());
        // allow sequencer to transfer shares
        if (sequencer == operator) {
            return true;
        }
        if (account == sequencer && address(vamm) == operator) {
            return true;
        }
        return super.isApprovedForAll(account, operator);
    }

    /**
     * @dev Clock used for flagging checkpoints. Can be overridden to implement timestamp based
     * checkpoints (and voting), in which case {CLOCK_MODE} should be overridden as well to match.
     */
    function clock() public view override returns (uint48) {
        return SafeCast.toUint48(block.number);
    }

    /**
     * @dev Machine-readable description of the clock as specified in EIP-6372.
     */
    // solhint-disable-next-line func-name-mixedcase
    function CLOCK_MODE() public view override returns (string memory) {
        // Check that the clock was not modified
        require(clock() == block.number, "Votes: broken clock mode");
        return "mode=blocknumber&from=default";
    }

    /**
     * @dev Transfers, mints, or burns units. To register a mint, `from` should be zero. To register a burn, `to`
     * should be zero. Total supply of units will be adjusted with mints and burns.
     */
    function _transferUnits(
        uint256 id,
        address from,
        address to,
        uint256 amount
    ) internal virtual {
        if (from == address(0)) {
            _push(_totalCheckpoints[id], _add, SafeCast.toUint224(amount));
        }
        if (to == address(0)) {
            _push(_totalCheckpoints[id], _subtract, SafeCast.toUint224(amount));
        }
        _moveBalance(id, from, to, amount);
    }

    /**
     * @dev Moves balance between accounts, adjusting vote counts.
     * If the `from` account is the zero address, minting is assumed.
     * If the `to` account is the zero address, burning is assumed.
     */
    function _moveBalance(
        uint256 id,
        address from,
        address to,
        uint256 amount
    ) private {
        if (from != to && amount > 0) {
            if (from != address(0)) {
                (, uint224 newBalance) = _push(
                    _balanceCheckpoints[id][from],
                    _subtract,
                    SafeCast.toUint224(amount)
                );
                // If the user's balance is zero, decrease the number of members
                if (newBalance == 0) {
                    _push(
                        _membersCheckpoints[id],
                        _subtract,
                        SafeCast.toUint224(1)
                    );
                }
            }
            if (to != address(0)) {
                (uint224 previousBalance, ) = _push(
                    _balanceCheckpoints[id][to],
                    _add,
                    SafeCast.toUint224(amount)
                );
                if (previousBalance == 0) {
                    _push(_membersCheckpoints[id], _add, SafeCast.toUint224(1));
                }
            }
        }
    }

    function _push(
        Checkpoints.Trace224 storage store,
        function(uint224, uint224) view returns (uint224) op,
        uint224 delta
    ) private returns (uint224, uint224) {
        return
            store.push(SafeCast.toUint32(clock()), op(store.latest(), delta));
    }

    function _add(uint224 a, uint224 b) private pure returns (uint224) {
        return a + b;
    }

    function _subtract(uint224 a, uint224 b) private pure returns (uint224) {
        return a - b;
    }

    // Get the user's balance under a specific blockNumber
    // If zero blockNumber is passed, it will return the latest balance
    function balanceOf(
        address account,
        uint256 id,
        uint256 blockNumber
    ) public view returns (uint256) {
        if (blockNumber == 0) {
            return balanceOf(account, id);
        }
        require(blockNumber < clock(), "Shares: balance future lookup");
        return
            _balanceCheckpoints[id][account].upperLookupRecent(
                SafeCast.toUint32(blockNumber)
            );
    }

    function balanceOf(
        address account,
        address shareId,
        uint256 blockNumber
    ) public view returns (uint256) {
        uint256 id = convertSharesId(shareId);
        return balanceOf(account, id, blockNumber);
    }

    // Get the total supply under a specific blockNumber
    // If zero blockNumber is passed, it will return the latest total supply
    function totalSupply(
        uint256 id,
        uint256 blockNumber
    ) public view returns (uint256) {
        if (blockNumber == 0) {
            return totalSupply(id);
        }
        require(blockNumber < clock(), "Shares: supply future lookup");
        return
            _totalCheckpoints[id].upperLookupRecent(
                SafeCast.toUint32(blockNumber)
            );
    }

    function totalSupply(uint256 id) public view returns (uint256) {
        return _totalCheckpoints[id].latest();
    }

    function totalSupply(
        address shareId,
        uint256 blockNumber
    ) public view returns (uint256) {
        uint256 id = convertSharesId(shareId);
        return totalSupply(id, blockNumber);
    }

    // Get the total supply under a specific blockNumber
    function convertSharesId(address shareId) public pure returns (uint256) {
        uint256 id = uint256(uint160(shareId));
        require(address(uint160(id)) == shareId, "Shares: id overflow");
        return id;
    }

    // Get the members under a specific blockNumber
    // If zero blockNumber is passed, it will return the latest total supply
    function members(
        uint256 id,
        uint256 blockNumber
    ) public view returns (uint256) {
        if (blockNumber == 0) {
            return members(id);
        }
        require(blockNumber < clock(), "Shares: members future lookup");
        return
            _membersCheckpoints[id].upperLookupRecent(
                SafeCast.toUint32(blockNumber)
            );
    }

    function members(uint256 id) public view returns (uint256) {
        return _membersCheckpoints[id].latest();
    }

    function members(
        address shareId,
        uint256 blockNumber
    ) public view returns (uint256) {
        uint256 id = convertSharesId(shareId);
        return members(id, blockNumber);
    }

    /**
     * @dev Indicates whether any token exist with a given id, or not.
     */
    function exists(uint256 id) external view returns (bool) {
        return totalSupply(id) > 0;
    }

    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyOwner {}

    function _isHolder(address account) internal view returns (bool) {
        return _holder[account] || account == _config.getSequencer();
    }

    function _afterTokenTransfer(
        address operator,
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data
    ) internal virtual override(ERC1155Upgradeable) {
        require(
            ids.length == amounts.length,
            "Shares: ids and amounts length mismatch"
        );
        require(
            from == address(0) || to == address(0) || _isHolder(to),
            "Shares: only registered holder can receive shares"
        );
        for (uint256 i = 0; i < ids.length; ++i) {
            uint256 id = ids[i];
            _transferUnits(id, from, to, amounts[i]);

            if (from != address(0)) {
                require(
                    balanceOf(from, id) ==
                        _balanceCheckpoints[id][from].latest(),
                    "Shares: invalid checkpoint"
                );
            }
        }
        super._afterTokenTransfer(operator, from, to, ids, amounts, data);
    }

    function _beforeTokenTransfer(
        address operator,
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data
    ) internal override(ERC1155Upgradeable) {
        super._beforeTokenTransfer(operator, from, to, ids, amounts, data);
    }

    function mint(
        address shareId,
        address to,
        uint256 amount
    ) external onlyVamm {
        uint256 id = convertSharesId(shareId);
        _mint(to, id, amount, "");
    }

    function burnFrom(
        address shareId,
        address account,
        uint256 amount
    ) external onlyVamm {
        uint256 id = convertSharesId(shareId);
        _burn(account, id, amount);
    }
}

