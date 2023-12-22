pragma solidity 0.8.16;

import "./IVotingEscrow.sol";
import "./IVeDist.sol";
import "./ILpDepositor.sol";
import "./ISplitter.sol";

import "./ERC20Upgradeable.sol";
import "./ERC20BurnableUpgradeable.sol";
import "./OwnableUpgradeable.sol";
import "./Initializable.sol";
import "./SafeERC20Upgradeable.sol";

import "./console.sol";

contract VeDepositor is
    Initializable,
    ERC20Upgradeable,
    ERC20BurnableUpgradeable,
    OwnableUpgradeable
{
    using SafeERC20Upgradeable for IERC20Upgradeable;

    // Solidly contracts
    IERC20Upgradeable public token;
    IVotingEscrow public votingEscrow;
    IVeDist public veDistributor;

    // monolith contracts
    ILpDepositor public lpDepositor;
    ISplitter public splitter;

    uint256 public tokenID;
    uint256 public unlockTime;

    // uint256 public constant WEEK = 1 weeks;
    uint256 public constant WEEK = 24 * 60 * 60; // for arbitrum test
    uint256 public constant MAX_LOCK_TIME = 4 * 52 * WEEK;

    event ClaimedFromVeDistributor(address indexed user, uint256 amount);
    event Merged(address indexed user, uint256 tokenID, uint256 amount);
    event UnlockTimeUpdated(uint256 unlockTime);

    function initialize(
        IERC20Upgradeable _token,
        IVotingEscrow _votingEscrow,
        IVeDist _veDist
    ) public initializer {
        __Ownable_init();
        __ERC20_init("moSOLID: Tokenized veSOLID", "moSOLID");

        token = _token;
        votingEscrow = _votingEscrow;
        veDistributor = _veDist;

        // approve vesting escrow to transfer SOLID (for adding to lock)
        _token.approve(address(_votingEscrow), type(uint256).max);
    }

    function setAddresses(
        ILpDepositor _lpDepositor,
        ISplitter _splitter
    ) external onlyOwner {
        lpDepositor = _lpDepositor;
        splitter = _splitter;
    }

    function onERC721Received(
        address _operator,
        address _from,
        uint256 _tokenID,
        bytes calldata
    ) external returns (bytes4) {
        require(
            msg.sender == address(votingEscrow),
            "Can only receive veSOLID NFTs"
        );

        require(_tokenID > 0, "Cannot receive zero tokenID");

        (uint256 amount, uint256 end) = votingEscrow.locked(_tokenID);

        if (tokenID == 0) {
            tokenID = _tokenID;
            unlockTime = end;
            votingEscrow.safeTransferFrom(
                address(this),
                address(lpDepositor),
                _tokenID
            );
        } else {
            votingEscrow.merge(_tokenID, tokenID);
            if (end > unlockTime) unlockTime = end;
            emit Merged(_operator, _tokenID, amount);
        }

        _mint(_operator, amount);
        extendLockTime();

        return
            bytes4(
                keccak256("onERC721Received(address,address,uint256,bytes)")
            );
    }

    /**
        @notice Merge a veSOLID NFT previously sent to this contract
                with the main monolith NFT
        @dev This is primarily meant to allow claiming balances from NFTs
             incorrectly sent using `transferFrom`. To deposit an NFT
             you should always use `safeTransferFrom`.
        @param _tokenID ID of the NFT to merge
        @return bool success
     */
    function merge(uint256 _tokenID) external returns (bool) {
        require(tokenID != _tokenID);
        (uint256 amount, uint256 end) = votingEscrow.locked(_tokenID);
        require(amount > 0);

        votingEscrow.merge(_tokenID, tokenID);
        if (end > unlockTime) unlockTime = end;
        emit Merged(msg.sender, _tokenID, amount);

        _mint(msg.sender, amount);
        extendLockTime();

        return true;
    }

    /**
        @notice Deposit SOLID tokens and mint moSolid
        @param _amount Amount of SOLID to deposit
        @return bool success
     */
    function depositTokens(uint256 _amount) external returns (bool) {
        require(tokenID != 0, "First deposit must be NFT");

        token.transferFrom(msg.sender, address(this), _amount);
        votingEscrow.increase_amount(tokenID, _amount);
        _mint(msg.sender, _amount);
        extendLockTime();

        return true;
    }

    /**
        @notice Extend the lock time of the protocol's veSOLID NFT
        @dev Lock times are also extended each time new moSolid is minted.
             If the lock time is already at the maximum duration, calling
             this function does nothing.
     */
    function extendLockTime() public {
        uint256 maxUnlock = ((block.timestamp + MAX_LOCK_TIME) / WEEK) * WEEK;
        if (maxUnlock > unlockTime) {
            votingEscrow.increase_unlock_time(tokenID, MAX_LOCK_TIME);
            unlockTime = maxUnlock;
            emit UnlockTimeUpdated(unlockTime);
        }
    }

    /**
        @notice Claim veSOLID received via ve(3,3)
        @dev This function is unguarded, anyone can call to claim at any time.
             The new veSOLID is represented by newly minted moSolid, which is
             then sent to `FeeDistributor` and streamed to moSolid stakers starting
             at the beginning of the following epoch week.
     */
    function claimFromVeDistributor() external returns (bool) {
        veDistributor.claim(tokenID);

        // calculate the amount by comparing the change in the locked balance
        // to the known total supply, this is necessary because anyone can call
        // `veDistributor.claim` for any NFT
        (uint256 amount, ) = votingEscrow.locked(tokenID);
        amount -= totalSupply() + splitter.totalSplitRequested();

        if (amount > 0) {
            _mint(address(this), amount);
        }

        return true;
    }
}

