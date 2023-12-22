//SPDX-License-Identifier: Unlicense

pragma solidity 0.8.18;

import "./ISpartans.sol";
import "./ISpartansMinter.sol";
import "./MerkleProof.sol";
import "./Ownable.sol";
import "./IERC721Receiver.sol";

contract SpartansMinter is ISpartansMinter, IERC721Receiver, Ownable {
    uint256 public constant TEAM_TOKENS_AMOUNT = 255;
    uint256 public constant SALE_TOKENS_AMOUNT = 5300;
    uint256 public constant TOKENS_AMOUNT =
        TEAM_TOKENS_AMOUNT + SALE_TOKENS_AMOUNT;

    bool internal _teamTokensMinted = false;
    address internal immutable _treasuryWallet;
    ISpartans public immutable override spartans;
    uint256 public immutable whitelistMintingStart;
    uint256 public immutable whitelistMintingDuration;
    uint256 public immutable publicMintingDuration;
    uint256 public immutable walletLimit;
    uint256 public immutable whitelistMintingPrice;
    uint256 public immutable publicMintingPrice;
    bytes32 internal immutable _merkleRoot;
    uint256 public mintedCounter;

    mapping(address => uint256) public tokensToClaim;
    mapping(address => mapping(uint256 => uint256)) userTokens;

    constructor(
        address treasuryWallet_,
        ISpartans spartans_,
        address owner_,
        uint256 whitelistMintingPrice_,
        uint256 publicMintingPrice_,
        uint256 whitelistMintingStart_,
        uint256 whitelistMintingDuration_,
        uint256 publicMintingDuration_,
        uint256 walletLimit_,
        bytes32 merkleRoot_
    ) {
        _treasuryWallet = treasuryWallet_;
        whitelistMintingStart = whitelistMintingStart_;
        whitelistMintingDuration = whitelistMintingDuration_;
        publicMintingDuration = publicMintingDuration_;

        walletLimit = walletLimit_;
        _merkleRoot = merkleRoot_;
        spartans = spartans_;
        whitelistMintingPrice = whitelistMintingPrice_;
        publicMintingPrice = publicMintingPrice_;

        _transferOwnership(owner_);
    }

    function onERC721Received(
        address,
        address,
        uint256,
        bytes memory
    ) public virtual override returns (bytes4) {
        return this.onERC721Received.selector;
    }

    function mintForTeam(
        address to
    ) external onlyOwner onlyIfTeamTokenNotMinted {
        spartans.safeMint(to, TEAM_TOKENS_AMOUNT);
        mintedCounter += TEAM_TOKENS_AMOUNT;
        _teamTokensMinted = true;
    }

    function state() public view override returns (State) {
        if (allTokensMinted()) {
            return State.FINISHED;
        } else if (block.timestamp < whitelistMintingStart) {
            return State.NOT_STARTED;
        } else if (isWhitelistMinting()) {
            return State.WHITELIST_MINT;
        } else if (isPublicMinting()) {
            return State.PUBLIC_MINT;
        }

        return State.FINISHED;
    }

    function isWhitelistMinting() public view override returns (bool) {
        return
            block.timestamp > whitelistMintingStart &&
            block.timestamp < whitelistMintingEndTimestamp();
    }

    function isPublicMinting() public view override returns (bool) {
        return
            block.timestamp > whitelistMintingEndTimestamp() &&
            block.timestamp < publicMintingEndTimestamp();
    }

    function whitelistMintingEndTimestamp()
        public
        view
        override
        returns (uint256)
    {
        return whitelistMintingStart + whitelistMintingDuration;
    }

    function publicMintingEndTimestamp()
        public
        view
        override
        returns (uint256)
    {
        return
            whitelistMintingStart +
            whitelistMintingDuration +
            publicMintingDuration;
    }

    function allTokensMinted() public view override returns (bool) {
        return mintedCounter == TOKENS_AMOUNT;
    }

    modifier onlyIfState(State expectedState) {
        State _state = state();
        if (_state != expectedState) {
            revert WrongState(expectedState, _state);
        }

        _;
    }

    modifier onlyIfTeamTokenNotMinted() {
        if (_teamTokensMinted) {
            revert TeamTokensAlreadyMinted();
        }

        _;
    }

    modifier walletLimitNotExceeded(uint256 amount) {
        if (tokensToClaim[msg.sender] + amount > walletLimit) {
            revert WalletLimitExceeded();
        }
        _;
    }

    modifier tokensLimitNotExceeded(uint256 amount) {
        if (mintedCounter + amount > TOKENS_AMOUNT) {
            revert TokensLimitExceeded();
        }
        _;
    }

    modifier msgValueIsCorrect(uint256 expected) {
        uint256 value = msg.value;

        if (value < expected) {
            revert WrongMsgValue(expected, value);
        }
        _;
    }

    modifier onlyIfOnWhitelist(bytes32[] memory proof_) {
        if (
            !MerkleProof.verify(
                proof_,
                _merkleRoot,
                keccak256(abi.encodePacked(msg.sender))
            )
        ) {
            revert UserNotWhitelisted();
        }
        _;
    }

    function _prevalidateMintingLimits(uint256 amount) internal view {
        if (tokensToClaim[msg.sender] + amount > walletLimit) {
            revert WalletLimitExceeded();
        }
    }

    function _afterMint(address sender, uint256 amount) internal {
        for (uint256 i = 0; i < amount; ) {
            userTokens[sender][i] = mintedCounter + i + 1;
            unchecked {
                ++i;
            }
        }

        tokensToClaim[sender] += amount;
        mintedCounter += amount;
    }

    function _mint(address to, uint256 amount) internal {
        spartans.safeMint(address(this), amount);
        _afterMint(to, amount);
    }

    function publicMint(
        uint256 amount
    )
        external
        payable
        override
        onlyIfState(State.PUBLIC_MINT)
        msgValueIsCorrect(publicMintingPrice * amount)
        walletLimitNotExceeded(amount)
        tokensLimitNotExceeded(amount)
    {
        address sender = msg.sender;
        _mint(sender, amount);

        emit TokensMinted(sender, State.PUBLIC_MINT, amount);
    }

    function whitelistMint(
        uint256 amount,
        bytes32[] memory proof_
    )
        external
        payable
        onlyIfState(State.WHITELIST_MINT)
        msgValueIsCorrect(whitelistMintingPrice * amount)
        onlyIfOnWhitelist(proof_)
        walletLimitNotExceeded(amount)
        tokensLimitNotExceeded(amount)
    {
        address sender = msg.sender;
        _mint(sender, amount);

        emit TokensMinted(sender, State.WHITELIST_MINT, amount);
    }

    function claim() external onlyIfState(State.FINISHED) {
        address sender = msg.sender;
        uint256 amountOfTokensToClaim = tokensToClaim[sender];
        if (amountOfTokensToClaim == 0) {
            revert NothingToClaim();
        }

        for (uint256 i = 0; i < amountOfTokensToClaim; ) {
            spartans.safeTransferFrom(
                address(this),
                sender,
                userTokens[sender][i]
            );
            unchecked {
                ++i;
            }
        }
    }

    function withdraw() external onlyOwner {
        (bool sent, ) = _treasuryWallet.call{value: address(this).balance}("");
        if (!sent) {
            revert WithdrawFailure();
        }
    }
}

