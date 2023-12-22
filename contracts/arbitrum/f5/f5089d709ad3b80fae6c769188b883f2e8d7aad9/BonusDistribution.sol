// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./IBonusDistribution.sol";
import "./LibString.sol";
import "./LockBox.sol";
// For debugging only


/**
 * @title Bonus distribution handler.
 * @author Deepp Dev Team
 * @notice Contract for storing and releasing bonus tokens.
 * @notice Its keeps a list of portions of locked tokens and owns the tokens.
 * @notice LockBox is TokenValidator is Accesshandler is Initializable.
 */
contract BonusDistribution is IBonusDistribution, LockBox {
    using LibString for string;

    // Holds the number of defined portions.
    uint8 public numPortions;

    // Holds the id of the current portion, or the latest finished one.
    uint8 public currentPortion;

    // Holds the amount of progress that has been released as bonus for current portion.
    // Can be used to determine, when all progress is converted to released bonus.
    uint256 private releasedProgress;

    // Holds the amount of claimed bonus per token.
    // token => amount
    mapping(address => uint256) private claimedBonus;

    // Holds the amount of added bonus per token.
    // token => amount
    mapping(address => uint256) private addedBonus;

    // Holds the amount of released bonus, per token.
    // token => amount
    mapping(address => uint256) private releasedBonus; // Only used for external info

    // Holds the progress per user for the current bonus portion.
    // account => amount
    mapping(address => uint256) private userProgress;

    // Holds the amount of available bonus.
    // token => account => amount
    mapping(address => mapping(address => uint256)) private availableBonus;

    // Array that holds all defined bonus portions.
    BonusPortion[] private portions;

    /**
     * @notice Event fires when bonus is claimed, including 0 claims.
     * @param owner is the owner of the bonus/claim.
     * @param token is the token contract address.
     * @param amount is the token amount claimed.
     */
    event BonusClaimed(
        address indexed owner,
        address token,
        uint256 amount
    );

    /**
     * @notice Event fires when bonus progress is increased.
     * @param id is the id of the portion.
     * @param account is the provider of the progress (future bonus recipient).
     * @param amount is the new progress increase.
     */
    event BonusProgress(
        uint8 indexed id,
        address indexed account,
        uint256 amount
    );

    /**
     * @notice Event fires when portion changes state.
     * @param id is the id of the portion changing.
     * @param state is the new state of the portion.
     */
    event BonusPortionState(uint8 indexed id, BonusState state);

    /**
     * @notice Event fires when portion reaches the target progress.
     * @param id is the id of the portion completed.
     * @param progress is the progress reached.
     */
    event BonusPortionCompleted(
        uint8 indexed id,
        uint256 progress
    );

    /**
     * @notice Event fires when a part of a portion is released.
     * @param id is the id of the portion affected.
     * @param token is the bonus token contract address.
     * @param amount is the bonus token amount released.
     * @param recipients is the number of bonus recipients.
     */
    event BonusReleased(
        uint8 indexed id,
        address token,
        uint256 amount,
        uint256 recipients
    );

    /**
     * Error invalid bonus portion input.
     */
    error InvalidBonusPortion(string reason);

    /**
     * Error invalid state change.
     */
    error InvalidState(uint8 id, BonusState oldState, BonusState requestedState);

    /**
     * Error invalid bonus portion input.
     */
    error InsufficientBonus(uint8 id, uint256 required, uint256 available);

    /**
     * @notice Default constructor.
     */
    constructor() LockBox() {}

    /**
     * @notice Initializes this contract with reference to the bonus token.
     * @param inTokenAdd The token handled by this bonus system.
     */
    function init(address inTokenAdd) external notInitialized onlyRole(DEFAULT_ADMIN_ROLE)
    {
        // Add the token to the list of accepted input tokens.
        _addTokenPair(inTokenAdd, DUMMY_ADDRESS);

        _init();
    }

    /**
     * @notice Initializes this contract with reference to the bonus token.
     * @param id is an id of the portion, continous increasing from 1.
     * @param tokenAdd The token type that is paid for this bonus portion.
     * @param amount of tokens to payout out when the portion is released.
     * @param target is the process target to release the portion.
     */
    function addPortion(uint8 id, address tokenAdd, uint256 amount, uint256 target)
        external
        override
        onlyRole(BONUS_CONTROLLER_ROLE)
    {
        BonusPortion memory portion = BonusPortion({
            id: id,
            state: BonusState.Pending,
            tokenAdd: tokenAdd,
            amount: amount,
            released: 0,
            progress: 0,
            progressTarget: target
        });
        string memory result = validateNewPortion(portion);
        if (!result.equals("OK"))
            revert InvalidBonusPortion({reason: result});

        addedBonus[tokenAdd] += amount;
        _lock(address(this), tokenAdd, amount);
        portions.push(portion);
        numPortions++;
    }

    /**
     * @notice Claims an accounts available bonus, that was previously released.
     * @param tokenAdd The token type of the bonus to claim.
     */
    function claimBonus(address tokenAdd) external override whenNotPaused {
        address owner = msg.sender;
        uint256 amount = availableBonus[tokenAdd][owner];
        if (amount > 0) {
            claimedBonus[tokenAdd] += amount;
            availableBonus[tokenAdd][owner] = 0;
            _unlock(address(this), tokenAdd, amount);
            IERC20(tokenAdd).transfer(owner, amount);
        }
        emit BonusClaimed(owner, tokenAdd, amount);
    }

    /**
     * @notice Updates progress for the current bonus portion.
     * if the current portion is not Active, the input is ignored.
     * @param inAccount The account that provided the delta progress.
     * @param inNewProgress The new delta portion progress.
     */
    function updateProgress(address inAccount, uint256 inNewProgress)
        external
        override
        whenNotPaused
        onlyRole(BONUS_REPORTER_ROLE)
    {
        if (currentPortion == 0)
            return;

        BonusPortion storage portion =  portions[currentPortion - 1];
        if (portion.state != BonusState.Active)
            return;

        portion.progress += inNewProgress;
        userProgress[inAccount] += inNewProgress;
        emit BonusProgress(currentPortion, inAccount, inNewProgress);


        if (portion.progress >= portion.progressTarget) {
            portion.state = BonusState.Completed;
            emit BonusPortionState(portion.id, BonusState.Completed);
            emit BonusPortionCompleted(portion.id, portion.progress);
        }
    }

    /**
     * @notice Release bonus for a number of recipients.
     * @param inRecipients An array of addresses as recipients.
     */
    function releaseBonus(address[] calldata inRecipients) external override whenNotPaused {
        if (currentPortion == 0)
            revert InvalidBonusPortion({reason: "INVALID_ID"});
        BonusPortion storage portion =  portions[currentPortion - 1];
        if (portion.state != BonusState.Completed)
            revert InvalidBonusPortion({reason: "INVALID_STATE"});

        // Calc the relative bonus assignment using extra 10 digits decimal precission
        uint256 bonusPerProgress = portion.amount * 1e10 / portion.progress;



        uint256 released; // Combined released
        for(uint256 i=0; i<inRecipients.length; i++) {
            uint256 userProg = userProgress[inRecipients[i]];
            userProgress[inRecipients[i]] = 0;
            releasedProgress += userProg;
            uint256 userBonus = userProg * bonusPerProgress / 1e10; // remove the additional 10 digits precission again
            released += userBonus;

            availableBonus[portion.tokenAdd][inRecipients[i]] += userBonus; // Individual new available
        }
        uint256 remaining = portion.amount - portion.released;
        if (released > remaining || releasedProgress > portion.progress) {
            revert InsufficientBonus({
                id: portion.id,
                required: released,
                available: remaining
            });
        }
        portion.released += released;
        releasedBonus[portion.tokenAdd] += released;

        emit BonusReleased(
            portion.id,
            portion.tokenAdd,
            released,
            inRecipients.length);

        if (portion.progress == releasedProgress) {
            // All have been released, switch state
            portion.state = BonusState.Released;
            emit BonusPortionState(portion.id, BonusState.Released);

        }
    }

    /**
     * @notice Updates a portion to a new state.
     * @notice Revert Error is emitted if state change is not allowed.
     * @param inId The bonus portion to update.
     * @param inState The new state for the portion.
     */
    function setPortionState(uint8 inId, BonusState inState) external override onlyRole(BONUS_CONTROLLER_ROLE) {
        // Check that portion is valid
        if (inId == 0 || inId > numPortions) {
            revert InvalidBonusPortion({reason: "INVALID_ID"});
        }
        BonusPortion storage portion = portions[inId - 1];
        bool success = false;
        if (portion.state == BonusState.Pending && inState == BonusState.Active) {
            // First portion or previous portion was Released ?
            if (inId == 1 || portions[inId - 2].state == BonusState.Released) {
                success = true;
                releasedProgress = 0;
                currentPortion = inId;
            }
        }
        else if (portion.state == BonusState.Active && inState == BonusState.Completed) {
            if (portion.progress >= portion.progressTarget) // Automatically done in updateProgress()
                success = true;
        }
        else if (portion.state == BonusState.Completed && inState == BonusState.Released) {
            if (portion.progress == releasedProgress) // Automatically done in releaseBonus()
                success = true;
        }

        if (success) {
            portion.state = inState;
            emit BonusPortionState(inId, inState);
        }
        else {
            revert InvalidState({
                id: inId,
                oldState: portion.state,
                requestedState: inState
            });
        }
    }

    /**
     * @notice Gets the full data of a portion.
     * @param id The is of the requested portion.
     * @return BonusPortion The data details.
     */
    function getPortion(uint8 id) external view override returns (BonusPortion memory) {
        return portions[id - 1];
    }

    /**
     * @notice Gets a struct of combined data.
     * @param tokenAdd The token type of balances.
     * @return CombinedBonusData The combined data.
     */
    function getCombinedData(address tokenAdd)
        external
        view
        override
        returns (CombinedBonusData memory)
    {
        CombinedBonusData memory data = CombinedBonusData({
            numPortions: numPortions,
            currentPortion: currentPortion,
            claimedBonus: claimedBonus[tokenAdd],
            addedBonus: addedBonus[tokenAdd],
            releasedBonus: releasedBonus[tokenAdd],
            portions: portions
        });
        return data;
    }

    /**
     * @notice Gets a struct of user data: Current portion prog and available bonus.
     * @param inAccount The account to get data for.
     * @param tokenAdd The token type of available bonus.
     * @return UserBonusData The combined user data.
     */
    function getUserData(address inAccount, address tokenAdd)
        external
        view
        override
        returns (UserBonusData memory)
    {
        UserBonusData memory data = UserBonusData({
            progress: userProgress[inAccount],
            availableBonus: availableBonus[tokenAdd][inAccount]
        });
        return data;
    }

    /**
     * @notice Checks the parameters of a new portion to see if they are valid.
     * @notice Note that balances are checked, to tokens must be available.
     * @param inPortion is the portion to check.
     * @return string A status string in UPPER_SNAKE_CASE.
     *         It will return "OK" if everything checks out.
     */
    function validateNewPortion(BonusPortion memory inPortion) private view returns (string memory) {
        if (inPortion.id != numPortions + 1) {return "INVALID_ID";}
        if (inPortion.progressTarget == 0) {return "INVALID_PROGRESS_TARGET";}

        uint256 amount = inPortion.amount;
        address token = inPortion.tokenAdd;
        if (amount == 0) {return "BONUS_AMOUNT_ZERO";}
        if (!_isAllowedToken(token)) {return "INVALID_TOKEN";}
        // Added - claimed is the same as locked token owned by this
        uint256 requiredAmount = addedBonus[token] - claimedBonus[token] + amount;
        uint256 balance = IERC20(token).balanceOf(address(this));
        if (requiredAmount > balance) {return "BONUS_NOT_AVAILABLE";}

        return "OK";
    }
}
