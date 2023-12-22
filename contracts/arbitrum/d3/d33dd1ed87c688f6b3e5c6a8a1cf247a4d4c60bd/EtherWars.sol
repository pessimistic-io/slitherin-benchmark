// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import "./Ownable.sol";
import "./ReentrancyGuard.sol";

interface IEtherWarsQrng {
    function makeRequestUint256Array(
        uint256 _size,
        address _attacker,
        string memory _name,
        uint256 _faction
    ) external;
}

contract EtherWars is Ownable, ReentrancyGuard {
    address[] public list;
    IEtherWarsQrng public qrngConsumer;

    address public spinToWinContract;

    uint256 public devFeePercentage = 5;
    uint256 public currentDevFees;
    uint256 public minimumStrength = 0.01 ether;
    uint256 public maximumStrength = type(uint256).max;
    uint256 public redemptionPointsCost = 250;
    uint256 public cooldownReduction = 60 minutes;
    uint256 public cooldownTime = 1 days;
    uint256 public redemptionPercentage = 0;
    uint256 public attackMultiplier = 4;
    uint256 public maxRandomNum = 1000;
    uint256 public spinCountWinner = 5;
    uint256 public spinCountLoser = 3;

    struct UserProfile {
        string name;
        uint256 faction;
    }

    mapping(string => bool) public nameList;
    mapping(address => UserProfile) public contenderProfiles;
    mapping(address => uint256) public contenderStrength;
    mapping(address => uint256) public contenderCooldown;
    mapping(address => uint256) public contenderRedemptionPoints;
    mapping(address => uint256) public contenderListPosition;
    mapping(address => uint256) public spinPoints;
    mapping(address => uint256) public lifetimeEthWagered;
    mapping(address => uint256) public lifetimeSpinPoints;
    mapping(address => bool) public withdrawActive;

    bool public isOnline = false;
    bool public activeWinChanceAttacker = true;
    bool public activeWinChanceDefender = true;

    event NewContender(
        address indexed contender,
        string username,
        uint256 faction,
        uint256 contenderStrength
    );
    event CombatResults(
        address indexed attacker,
        string attackerName,
        uint256 attackerFaction,
        address indexed defender,
        string defenderName,
        uint256 defenderFaction,
        uint256 attackChance,
        uint256 attackStrength,
        uint256 defenseStrength,
        uint256 randomOutcome
    );
    event UserWithdrawal(address indexed user, uint256 amount);
    event OwnerWithdrawal(uint256 currentDevFees);
    event PowerIncreased(address indexed contender, uint256 ethValue);
    event MaxStrengthSet(uint256 strength);
    event MinStrengthSet(uint256 strength);
    event DevFeeSet(uint256 fee);
    event RedemptionPercentageSet(uint256 percentage);
    event RedemptionPointsCostSet(uint256 points);
    event CooldownReductionSet(uint256 cooldown);
    event CooldownTimeSet(uint256 time);
    event MaxRandomNumSet(uint256 num);
    event MinimumWinChanceToggle(bool attacker, bool defender);
    event SpinPointsSet(uint256 winner, uint256 loser);
    event WithdrawCooldownActivated(address user, uint256 contenderCooldown);
    event NewQRNGConsumer(address qrngConsumer);
    event NewAttackMultiplier(uint256 multiplier);
    event NewSpinToWinContract(address newAddress);
    event EtherWarsOnline();
    event EtherWarsOffline();

    error NotEnoughStrength();
    error StrengthTooHigh();
    error NotInList();
    error AttackerIsDefender();
    error AttackerTooWeak(uint256 strength, uint256 minimumStrength);
    error StillInCooldown(uint256 cooldownEnd, uint256 currentTime);
    error NotEnoughFunds();
    error NoAmountIncluded();
    error NotEnoughRedemptionPoints(uint256 redemptionPoints);
    error NotEnoughCooldownLeft();
    error AlreadyInArena();
    error NotQRNGConsumer();
    error ArenaOffline();
    error SendEthFailed(uint256 amount);
    error RedemptionNotActive();
    error SenderNotContender();
    error NotSpinToWinContract();
    error EmptyList();
    error EmptyName();
    error NameAlreadyExists();
    error WithdrawNotActive();
    error WithdrawAlreadyActivated();

    constructor(address _qrngConsumer) {
        require(_qrngConsumer != address(0), "Address 0");
        qrngConsumer = IEtherWarsQrng(_qrngConsumer);
    }

    modifier onlyQRNGConsumer() {
        if (IEtherWarsQrng(msg.sender) != qrngConsumer) revert NotQRNGConsumer();
        _;
    }

    modifier onlySpinToWin() {
        if (msg.sender != spinToWinContract) revert NotSpinToWinContract();
        _;
    }

    modifier checkArena() {
        if (!isOnline) revert ArenaOffline();
        _;
    }

    function enterArena(uint256 _faction, string calldata _username) external payable checkArena {
        address contender = msg.sender;
        // If contender already has an ETH balance in the contract, then combine that with the msg.value
        if (contenderStrength[contender] + msg.value < minimumStrength) revert NotEnoughStrength();
        if (contenderStrength[contender] + msg.value > maximumStrength) revert StrengthTooHigh();
        if (list.length > 0 && list[contenderListPosition[contender]] == contender) revert AlreadyInArena();

        if (bytes(_username).length == 0) revert EmptyName();
        if (nameList[_username]) revert NameAlreadyExists();

        if (withdrawActive[contender]) {
            delete withdrawActive[contender];
        }

        nameList[_username] = true;
        contenderProfiles[contender].name = _username;
        contenderProfiles[contender].faction = _faction;

        contenderListPosition[contender] = list.length;
        list.push(contender);
        contenderStrength[contender] += msg.value;
        lifetimeEthWagered[contender] += msg.value;

        emit NewContender(contender, _username, _faction, contenderStrength[contender]);
    }

    function attack() external nonReentrant checkArena {
        if (numberOfContenders() == 1) revert EmptyList();

        address attacker = msg.sender;

        if (list[contenderListPosition[attacker]] != attacker) revert NotInList();
        if (contenderStrength[attacker] < minimumStrength) revert NotEnoughStrength();

        if (withdrawActive[attacker]) {
            delete withdrawActive[attacker];
        }

        string memory username = contenderProfiles[attacker].name;
        uint256 faction = contenderProfiles[attacker].faction;
        removeFromList(attacker);
        qrngConsumer.makeRequestUint256Array(2, attacker, username, faction);
    }

    function beginCombat(
        address _attacker,
        string memory _username,
        uint256 _faction,
        uint256[] calldata _randomWords
    ) external onlyQRNGConsumer nonReentrant {
        address defender;
        uint256 randomOutcome;

        defender = list[_randomWords[0] % list.length];

        // Transform the result to a number between 1 and maxRandomNum inclusively to determine the winner
        randomOutcome = (_randomWords[1] % maxRandomNum) + 1;

        if (_attacker == defender) revert AttackerIsDefender();

        uint256 attackStrength = contenderStrength[_attacker];
        if (attackStrength < minimumStrength) revert AttackerTooWeak(attackStrength, minimumStrength);

        uint256 defenseStrength = contenderStrength[defender];
        uint256 attackCalculation = (attackStrength * maxRandomNum) / (attackStrength + defenseStrength);

        // Add attack multiplier to attack calculation and set a minimum chance to win
        uint256 attackChance = (attackCalculation * (100 + attackMultiplier)) / 100;

        // Ensure a minimum chance to win for the attacker
        if (activeWinChanceAttacker && attackChance < 1) {
            attackChance = 1;
        }

        // Ensure a minimum chance to win for the defender
        if (activeWinChanceDefender && attackChance > maxRandomNum) {
            attackChance = maxRandomNum;
        }

        emitCombatResult(
            _attacker,
            _username,
            _faction,
            defender,
            attackChance,
            attackStrength,
            defenseStrength,
            randomOutcome
        );

        uint256 devFee;

        // If the attacker wins
        if (randomOutcome < attackChance) {
            devFee = increaseWinnerStrength(_attacker, defender);

            if (contenderStrength[_attacker] >= maximumStrength) {
                removeFromList(defender);
            } else {
                // Remove defender from the queue, and replace defender's position with attacker
                list[contenderListPosition[defender]] = _attacker;
                contenderListPosition[_attacker] = contenderListPosition[defender];
                delete contenderListPosition[defender];
                // Add attacker's name and faction back to the profile
                nameList[_username] = true;
                contenderProfiles[_attacker].name = _username;
                contenderProfiles[_attacker].faction = _faction;
                // Remove defender profile
                delete nameList[contenderProfiles[defender].name];
                delete contenderProfiles[defender];
            }

            // Set defender's strength to 0
            delete contenderStrength[defender];

            // Defender earns redemption points equivalent to a % of the attacker's win chance
            if (redemptionPercentage > 0) {
                contenderRedemptionPoints[defender] =
                    contenderRedemptionPoints[defender] +
                    ((attackChance * redemptionPercentage) / 100);
            }
        } else {
            // If the defender wins
            devFee = increaseWinnerStrength(defender, _attacker);

            delete contenderStrength[_attacker];

            if (contenderStrength[defender] >= maximumStrength) {
                // The attacker was already removed in the attack() function
                // So we only need to remove the defender here
                removeFromList(defender);
            }

            // Attacker earns redemption points equivalent to a % of the defender's win chance
            if (redemptionPercentage > 0) {
                contenderRedemptionPoints[_attacker] =
                    contenderRedemptionPoints[_attacker] +
                    (((maxRandomNum - attackChance) * redemptionPercentage) / 100);
            }
        }

        currentDevFees += devFee;
    }

    function reduceCooldown() external nonReentrant checkArena {
        address user = msg.sender;

        if (!withdrawActive[user]) revert WithdrawNotActive();
        if (redemptionPercentage == 0) revert RedemptionNotActive();

        if (contenderRedemptionPoints[user] < redemptionPointsCost)
            revert NotEnoughRedemptionPoints(contenderRedemptionPoints[user]);
        if (contenderStrength[user] < minimumStrength)
            revert AttackerTooWeak(contenderStrength[user], minimumStrength);
        if ((contenderCooldown[user] - cooldownReduction) - block.timestamp < cooldownReduction)
            revert NotEnoughCooldownLeft();

        contenderRedemptionPoints[user] = contenderRedemptionPoints[user] - redemptionPointsCost;
        contenderCooldown[user] = contenderCooldown[user] - cooldownReduction;
    }

    function userWithdraw(uint256 _amount) external nonReentrant {
        address user = msg.sender;

        if (!withdrawActive[user]) revert WithdrawNotActive();
        if (_amount == 0) revert NoAmountIncluded();
        if (contenderCooldown[user] > block.timestamp)
            revert StillInCooldown(contenderCooldown[user], block.timestamp);
        if (contenderStrength[user] < _amount) revert NotEnoughFunds();

        delete withdrawActive[user];

        uint256 newStrength = contenderStrength[user] - _amount;

        // Remove user from the arena if strength is less then minimumAttack
        if (newStrength < minimumStrength) {
            removeFromList(user);
            // Use the player's entire balance for the withdrawal amount
            _amount = contenderStrength[user];
            delete contenderStrength[user];
        } else {
            contenderStrength[user] = contenderStrength[user] - _amount;
        }

        sendViaCall(payable(user), _amount);
        emit UserWithdrawal(user, _amount);
    }

    function activateWithdrawCooldown() external {
        address user = msg.sender;

        if (withdrawActive[user]) revert WithdrawAlreadyActivated();

        contenderCooldown[user] = block.timestamp + cooldownTime;
        withdrawActive[user] = true;
        emit WithdrawCooldownActivated(user, contenderCooldown[user]);
    }

    function increasePower(address _contender) external payable checkArena {
        if (list[contenderListPosition[_contender]] != _contender) revert NotInList();
        if (msg.sender != _contender) revert SenderNotContender();

        if (withdrawActive[_contender]) {
            delete withdrawActive[_contender];
        }

        contenderStrength[_contender] += msg.value;
        lifetimeEthWagered[_contender] += msg.value;
        emit PowerIncreased(_contender, msg.value);
    }

    function changeUsername(string calldata _newName) external {
        if (bytes(_newName).length == 0) revert EmptyName();
        if (nameList[_newName]) revert NameAlreadyExists();

        address user = msg.sender;
        if (list[contenderListPosition[user]] != user) revert NotInList();

        string memory previousName = contenderProfiles[user].name;
        delete nameList[previousName];

        nameList[_newName] = true;
        contenderProfiles[user].name = _newName;
    }

    function deductSpinPoints(address _user, uint256 _points) external onlySpinToWin {
        spinPoints[_user] -= _points;
    }

    function ownerWithdrawFees() external onlyOwner {
        uint256 amount = currentDevFees;
        currentDevFees = 0;
        sendViaCall(payable(owner()), amount);
        emit OwnerWithdrawal(amount);
    }

    function setMaximumStrength(uint256 _maxStrength) external onlyOwner {
        require(_maxStrength != 0, "Strength 0");
        require(minimumStrength < _maxStrength, "Strength too low");
        maximumStrength = _maxStrength;
        emit MaxStrengthSet(_maxStrength);
    }

    function setMinimumStrength(uint256 _minStrength) external onlyOwner {
        require(_minStrength != 0, "Strength 0");
        require(_minStrength < maximumStrength, "Strength too high");
        minimumStrength = _minStrength;
        emit MinStrengthSet(_minStrength);
    }

    function setDevFee(uint256 _devFee) external onlyOwner {
        require(_devFee <= 10, "Too high");
        devFeePercentage = _devFee;
        emit DevFeeSet(_devFee);
    }

    function setRedemptionPercentage(uint256 _percentage) external onlyOwner {
        require(_percentage <= 100, "Too high");
        redemptionPercentage = _percentage;
        emit RedemptionPercentageSet(_percentage);
    }

    function setRedemptionPointsCost(uint256 _cost) external onlyOwner {
        redemptionPointsCost = _cost;
        emit RedemptionPointsCostSet(_cost);
    }

    function setCooldownReduction(uint256 _time) external onlyOwner {
        cooldownReduction = _time;
        emit CooldownReductionSet(_time);
    }

    function setCooldownTime(uint256 _time) external onlyOwner {
        require(_time < 3 days, "Too long");
        cooldownTime = _time;
        emit CooldownTimeSet(_time);
    }

    function setQRNGConsumer(address _qrngConsumer) external onlyOwner {
        require(_qrngConsumer != address(0), "Address 0");
        qrngConsumer = IEtherWarsQrng(_qrngConsumer);
        emit NewQRNGConsumer(_qrngConsumer);
    }

    function setAttackMultiplier(uint256 _multiplier) external onlyOwner {
        attackMultiplier = _multiplier;
        emit NewAttackMultiplier(_multiplier);
    }

    function setSpinToWinContract(address _address) external onlyOwner {
        require(_address != address(0), "Address 0");
        spinToWinContract = _address;
        emit NewSpinToWinContract(_address);
    }

    function setMaxRandomNum(uint256 _num) external onlyOwner {
        maxRandomNum = _num;
        emit MaxRandomNumSet(_num);
    }

    function winChanceToggle(bool _attacker, bool _defender) external onlyOwner {
        activeWinChanceAttacker = _attacker;
        activeWinChanceDefender = _defender;
        emit MinimumWinChanceToggle(_attacker, _defender);
    }

    function enableArena() external onlyOwner {
        isOnline = true;
        emit EtherWarsOnline();
    }

    function disableArena() external onlyOwner {
        isOnline = false;
        emit EtherWarsOffline();
    }

    function setSpinPoints(uint256 _winner, uint256 _loser) external onlyOwner {
        spinCountWinner = _winner;
        spinCountLoser = _loser;
        emit SpinPointsSet(_winner, _loser);
    }

    function getFightList() external view returns (address[] memory) {
        return list;
    }

    function numberOfContenders() public view returns (uint256) {
        return list.length;
    }

    function removeFromList(address _contender) private {
        if (list[contenderListPosition[_contender]] == _contender) {
            // Add last contender in the list to the removed user's position
            list[contenderListPosition[_contender]] = list[list.length - 1];
            contenderListPosition[list[list.length - 1]] = contenderListPosition[_contender];
            list.pop();
            delete contenderListPosition[_contender];
            // Remove user profile
            string memory username = contenderProfiles[_contender].name;
            delete nameList[username];
            delete contenderProfiles[_contender];
        }
    }

    function increaseWinnerStrength(address _winner, address _loser) private returns (uint256) {
        // Some % fee taken from the defender
        uint256 devFee = (contenderStrength[_loser] * devFeePercentage) / 100;
        // Add loser's strength to winner, and subtract dev fee
        contenderStrength[_winner] = contenderStrength[_winner] + (contenderStrength[_loser] - devFee);
        // Add 5 spin points to winner and 3 to loser
        spinPoints[_winner] += spinCountWinner;
        lifetimeSpinPoints[_winner] += spinCountWinner;
        spinPoints[_loser] += spinCountLoser;
        lifetimeSpinPoints[_loser] += spinCountLoser;

        return devFee;
    }

    function sendViaCall(address payable _to, uint256 _amount) private {
        (bool sent, ) = _to.call{ value: _amount }("");
        if (!sent) revert SendEthFailed(_amount);
    }

    function emitCombatResult(
        address _attacker,
        string memory _attackerName,
        uint256 _attackerFaction,
        address _defender,
        uint256 attackChance,
        uint256 attackStrength,
        uint256 defenseStrength,
        uint256 randomOutcome
    ) private {
        string memory defenderName = contenderProfiles[_defender].name;
        uint256 defenderFaction = contenderProfiles[_defender].faction;

        emit CombatResults(
            _attacker,
            _attackerName,
            _attackerFaction,
            _defender,
            defenderName,
            defenderFaction,
            attackChance,
            attackStrength,
            defenseStrength,
            randomOutcome
        );
    }
}

