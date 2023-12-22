//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "./Ownable.sol";
import "./Counters.sol";
import "./IERC721.sol";
import "./ERC721Holder.sol";

// Interface for our erc20 token
interface IToken {
    function totalSupply() external view returns (uint256);

    function balanceOf(address tokenOwner)
        external
        view
        returns (uint256 balance);

    function allowance(address tokenOwner, address spender)
        external
        view
        returns (uint256 remaining);

    function transfer(address to, uint256 tokens)
        external
        returns (bool success);

    function approve(address spender, uint256 tokens)
        external
        returns (bool success);

    function transferFrom(
        address from,
        address to,
        uint256 tokens
    ) external returns (bool success);

    function mint(address to, uint256 amount) external;

    function burn(uint256 amount) external;

    function burnFrom(address account, uint256 amount) external;
}

interface iCUDLPets {
    function burn(uint256 token) external;
}

contract ArbiCudl is ERC721Holder, Ownable {
    address public MUSE_DAO;
    address public MUSE_DEVS;

    IToken public token;
    iCUDLPets public cudlPets;

    struct Pet {
        address nft;
        uint256 id;
    }

    mapping(address => bool) public supportedNfts;
    mapping(uint256 => Pet) public petDetails;

    // mining tokens
    mapping(uint256 => uint256) public lastTimeMined;

    // Pet properties
    mapping(uint256 => uint256) public timeUntilStarving;
    mapping(uint256 => uint256) public petScore;
    mapping(uint256 => bool) public petDead;
    mapping(uint256 => uint256) public timePetBorn;

    // items/benefits for the PET could be anything in the future.
    mapping(uint256 => uint256) public itemPrice;
    mapping(uint256 => uint256) public itemPoints;
    mapping(uint256 => string) public itemName;
    mapping(uint256 => uint256) public itemTimeExtension;

    mapping(uint256 => mapping(address => address)) public careTaker;

    mapping(address => mapping(uint256 => bool)) public isNftInTheGame; //keeps track if nft already played
    mapping(address => mapping(uint256 => uint256)) public nftToId; //keeps track if nft already played

    // whitelist contracts as operator

    mapping(address => bool) public isOperator;

    uint256 public giveLifePrice = 0;
    uint256 public feesEarned;
    using Counters for Counters.Counter;
    Counters.Counter private _tokenIds;
    Counters.Counter private _itemIds;

    event Mined(uint256 nftId, uint256 reward, address recipient);
    event BuyAccessory(
        uint256 nftId,
        uint256 itemId,
        uint256 amount,
        uint256 itemTimeExtension,
        address buyer
    );
    event Fatalize(uint256 opponentId, uint256 nftId, address killer);
    event NewPlayer(
        address nftAddress,
        uint256 nftId,
        uint256 playerId,
        address owner
    );
    event Bonk(
        uint256 attacker,
        uint256 victim,
        uint256 winner,
        uint256 reward
    );

    // Rewards algorithm

    uint256 public la;
    uint256 public lb;
    uint256 public ra;
    uint256 public rb;

    address public lastBonker;

    bytes32 public OPERATOR_ROLE;

    constructor(address _token) {
        token = IToken(_token);

        la = 2;
        lb = 2;
        ra = 6;
        rb = 7;

        MUSE_DAO = 0x4B5922ABf25858d012d12bb1184e5d3d0B6D6BE4; //0x6fBa46974b2b1bEfefA034e236A32e1f10C5A148;
        MUSE_DEVS = 0x4B5922ABf25858d012d12bb1184e5d3d0B6D6BE4;

        // Add 6 accessories
        _itemIds.increment();
        uint256 newItemId = _itemIds.current();
        itemName[newItemId] = "bananuman";
        itemPrice[newItemId] = 0.5 ether;
        itemPoints[newItemId] = 100;
        itemTimeExtension[newItemId] = 5 minutes;

        _itemIds.increment();
        newItemId = _itemIds.current();
        itemName[newItemId] = "catnip";
        itemPrice[newItemId] = 0.6 ether;
        itemPoints[newItemId] = 190;
        itemTimeExtension[newItemId] = 1.5 days;

        _itemIds.increment();
        newItemId = _itemIds.current();
        itemName[newItemId] = "cucombre";
        itemPrice[newItemId] = 2 ether;
        itemPoints[newItemId] = 1;
        itemTimeExtension[newItemId] = 4 days;

        _itemIds.increment();
        newItemId = _itemIds.current();
        itemName[newItemId] = "moon milk";
        itemPrice[newItemId] = 5 ether;
        itemPoints[newItemId] = 1300;
        itemTimeExtension[newItemId] = 2 days;

        _itemIds.increment();
        newItemId = _itemIds.current();
        itemName[newItemId] = "thic duck";
        itemPrice[newItemId] = 0.8 ether;
        itemPoints[newItemId] = 50;
        itemTimeExtension[newItemId] = 3 days;

        _itemIds.increment();
        newItemId = _itemIds.current();
        itemName[newItemId] = "tuna";
        itemPrice[newItemId] = 10 ether;
        itemPoints[newItemId] = 2700;
        itemTimeExtension[newItemId] = 5 days;
    }

    modifier isAllowed(uint256 _id) {
        Pet memory _pet = petDetails[_id];
        address ownerOf = IERC721(_pet.nft).ownerOf(_pet.id);
        require(
            ownerOf == msg.sender || careTaker[_id][ownerOf] == msg.sender,
            "!owner"
        );
        _;
    }

    modifier onlyOperator() {
        require(
            isOperator[msg.sender],
            "Roles: caller does not have the OPERATOR role"
        );
        _;
    }

    // GAME ACTIONS

    //can mine once every 24 hours per token.
    function claimMiningRewards(uint256 nftId) public isAllowed(nftId) {
        require(isPetSafe(nftId), "Your pet is starving, you can't mine");
        require(
            block.timestamp >= lastTimeMined[nftId] + 1 days ||
                lastTimeMined[nftId] == 0,
            "Current timestamp is over the limit to claim the tokens"
        );

        //TODO THINK ABOUT THIS -  This is the case where the pet was hibernating so we put back his TOD to 1 day
        if (timeUntilStarving[nftId] > block.timestamp + 5 days) {
            timeUntilStarving[nftId] = block.timestamp + 1 days;
        }

        //reset last start mined so can't remine and cheat
        lastTimeMined[nftId] = block.timestamp;

        uint256 _reward = getRewards(nftId);

        // 10% fees are for dev/dao/projects
        token.mint(msg.sender, _reward);

        emit Mined(nftId, _reward, msg.sender);
    }

    // Buy accesory to the VNFT
    function buyAccesory(uint256 nftId, uint256 itemId) public {
        require(!petDead[nftId], "ded pet");

        uint256 amount = itemPrice[itemId];
        require(amount > 0, "item does not exist");

        // recalculate time until starving
        timeUntilStarving[nftId] = block.timestamp + itemTimeExtension[itemId];
        petScore[nftId] += itemPoints[itemId];

        token.burnFrom(msg.sender, amount);

        feesEarned += amount / 10;

        emit BuyAccessory(
            nftId,
            itemId,
            amount,
            itemTimeExtension[itemId],
            msg.sender
        );
    }

    function feedMultiple(uint256[] calldata ids, uint256[] calldata itemIds)
        external
    {
        for (uint256 i = 0; i < ids.length; i++) {
            buyAccesory(ids[i], itemIds[i]);
        }
    }

    function claimMultiple(uint256[] calldata ids) external {
        for (uint256 i = 0; i < ids.length; i++) {
            claimMiningRewards(ids[i]);
        }
    }

    //TOOD DECIDE FATALITY
    function fatality(uint256 _deadId, uint256 _tokenId) external {
        require(
            !isPetSafe(_deadId) && petDead[_deadId] == false,
            "The PET has to be starved to claim his points"
        );

        petScore[_tokenId] =
            petScore[_tokenId] +
            (((petScore[_deadId] * (20)) / (100)));

        petScore[_deadId] = 0;

        petDead[_deadId] = true;

        // If the pet is the native pets then burn them.
        address nft;
        uint256 nftId;
        (, , , , , , , , , nft, nftId, ) = getPetInfo(_deadId);
        if (nft == address(cudlPets)) {
            cudlPets.burn(nftId);
        }
        emit Fatalize(_deadId, _tokenId, msg.sender);
    }

    function getCareTaker(uint256 _tokenId, address _owner)
        public
        view
        returns (address)
    {
        return (careTaker[_tokenId][_owner]);
    }

    function setCareTaker(
        uint256 _tokenId,
        address _careTaker,
        bool clearCareTaker
    ) external isAllowed(_tokenId) {
        if (clearCareTaker) {
            delete careTaker[_tokenId][msg.sender];
        } else {
            careTaker[_tokenId][msg.sender] = _careTaker;
        }
    }

    // requires approval
    function giveLife(address nft, uint256 _id) external {
        require(IERC721(nft).ownerOf(_id) == msg.sender, "!OWNER");
        require(
            !isNftInTheGame[nft][_id],
            "this nft was already registered can't again"
        );
        require(supportedNfts[nft], "!forbidden");

        // burn 6 cudl to join
        if (nft != address(cudlPets)) {
            token.burnFrom(msg.sender, giveLifePrice);
        }

        uint256 newId = _tokenIds.current();
        // set the pet struct
        petDetails[newId] = Pet(nft, _id);

        nftToId[nft][_id] = newId;

        isNftInTheGame[nft][_id] = true;

        timeUntilStarving[newId] = block.timestamp + 3 days; //start with 3 days of life.
        timePetBorn[newId] = block.timestamp;

        emit NewPlayer(nft, _id, newId, msg.sender);

        _tokenIds.increment();
    }

    function isPetOwner(uint256 petId, address user)
        public
        view
        returns (bool)
    {
        Pet memory _pet = petDetails[petId];
        address ownerOf = IERC721(_pet.nft).ownerOf(_pet.id);
        return (ownerOf == user || careTaker[petId][ownerOf] == user);
    }

    // GETTERS
    // check that pet didn't starve
    function isPetSafe(uint256 _nftId) public view returns (bool) {
        uint256 _timeUntilStarving = timeUntilStarving[_nftId];
        if (
            (_timeUntilStarving != 0 && _timeUntilStarving >= block.timestamp)
        ) {
            return true;
        } else {
            return false;
        }
    }

    // Allowed contracts

    function burnScore(uint256 petId, uint256 amount) external onlyOperator {
        require(!petDead[petId]);

        petScore[petId] -= amount;
    }

    function addScore(uint256 petId, uint256 amount) external onlyOperator {
        require(!petDead[petId]);
        petScore[petId] += amount;
    }

    function addTOD(uint256 petId, uint256 duration) external onlyOperator {
        require(!petDead[petId]);
        timeUntilStarving[petId] += duration;
    }

    function burnTod(uint256 petId, uint256 duration) external onlyOperator {
        require(!petDead[petId]);
        timeUntilStarving[petId] -= duration;
    }

    // GETTERS

    function getPetInfo(uint256 _nftId)
        public
        view
        returns (
            uint256 _pet,
            bool _isStarving,
            uint256 _score,
            uint256 _level,
            uint256 _expectedReward,
            uint256 _timeUntilStarving,
            uint256 _lastTimeMined,
            uint256 _timepetBorn,
            address _owner,
            address _token,
            uint256 _tokenId,
            bool _isAlive
        )
    {
        Pet memory thisPet = petDetails[_nftId];

        _pet = _nftId;
        _isStarving = !this.isPetSafe(_nftId);
        _score = petScore[_nftId];
        _level = level(_nftId);
        _expectedReward = getRewards(_nftId);
        _timeUntilStarving = timeUntilStarving[_nftId];
        _lastTimeMined = lastTimeMined[_nftId];
        _timepetBorn = timePetBorn[_nftId];
        _owner = IERC721(thisPet.nft).ownerOf(thisPet.id);
        _token = petDetails[_nftId].nft;
        _tokenId = petDetails[_nftId].id;
        _isAlive = !petDead[_nftId];
    }

    // get the level the pet is on to calculate the token reward
    function getRewards(uint256 tokenId) public view returns (uint256) {
        // This is the formula to get token rewards R(level)=(level)*6/7+6
        uint256 _level = level(tokenId);
        if (_level == 1) {
            return 600000000000000000;
        }
        _level = (_level * 100000000000000000 * ra) / rb;
        return (_level + 500000000000000000);
    }

    // get the level the pet is on to calculate points
    function level(uint256 tokenId) public view returns (uint256) {
        // This is the formula L(x) = 2 * sqrt(x * 2)
        uint256 _score = petScore[tokenId] / 100;
        if (_score == 0) {
            return 1;
        }
        uint256 _level = sqrtu(_score * la);
        return (_level * lb);
    }

    // ADMIN

    function editCurves(
        uint256 _la,
        uint256 _lb,
        uint256 _ra,
        uint256 _rb
    ) external onlyOwner {
        la = _la;
        lb = _lb;
        ra = _ra;
        rb = _rb;
    }

    function changeToken(address newToken) external onlyOwner {
        token = IToken(newToken);
    }

    function setGiveLifePrice(uint256 _price) external onlyOwner {
        giveLifePrice = _price;
    }

    function setPets(address _pets) external onlyOwner {
        cudlPets = iCUDLPets(_pets);
    }

    // edit specific item in case token goes up in value and the price for items gets to expensive for normal users.
    function editItem(
        uint256 _id,
        uint256 _price,
        uint256 _points,
        string calldata _name,
        uint256 _timeExtension
    ) external onlyOwner {
        itemPrice[_id] = _price;
        itemPoints[_id] = _points;
        itemName[_id] = _name;
        itemTimeExtension[_id] = _timeExtension;
    }

    // to support more projects
    function setSupported(address _nft, bool isSupported) public onlyOwner {
        supportedNfts[_nft] = isSupported;
    }

    function addOperator(address _address, bool _isAllowed) public onlyOwner {
        isOperator[_address] = _isAllowed;
    }

    // add items/accessories
    function createItem(
        string calldata name,
        uint256 price,
        uint256 points,
        uint256 timeExtension
    ) external onlyOwner {
        _itemIds.increment();
        uint256 newItemId = _itemIds.current();
        itemName[newItemId] = name;
        itemPrice[newItemId] = price;
        itemPoints[newItemId] = points;
        itemTimeExtension[newItemId] = timeExtension;
    }

    function changeEarners(address _newAddress, address _dao) public {
        require(msg.sender == MUSE_DEVS, "!forbidden");
        MUSE_DEVS = _newAddress;
        MUSE_DAO = _dao;
    }

    // anyone can call this
    function claimEarnings() public {
        token.mint(address(this), feesEarned);
        feesEarned = 0;

        uint256 balance = token.balanceOf(address(this));
        token.transfer(MUSE_DAO, balance / 7);
        token.transfer(MUSE_DEVS, balance / 3);
    }

    function sqrtu(uint256 x) private pure returns (uint128) {
        if (x == 0) return 0;
        else {
            uint256 xx = x;
            uint256 r = 1;
            if (xx >= 0x100000000000000000000000000000000) {
                xx >>= 128;
                r <<= 64;
            }
            if (xx >= 0x10000000000000000) {
                xx >>= 64;
                r <<= 32;
            }
            if (xx >= 0x100000000) {
                xx >>= 32;
                r <<= 16;
            }
            if (xx >= 0x10000) {
                xx >>= 16;
                r <<= 8;
            }
            if (xx >= 0x100) {
                xx >>= 8;
                r <<= 4;
            }
            if (xx >= 0x10) {
                xx >>= 4;
                r <<= 2;
            }
            if (xx >= 0x8) {
                r <<= 1;
            }
            r = (r + x / r) >> 1;
            r = (r + x / r) >> 1;
            r = (r + x / r) >> 1;
            r = (r + x / r) >> 1;
            r = (r + x / r) >> 1;
            r = (r + x / r) >> 1;
            r = (r + x / r) >> 1; // Seven iterations should be enough
            uint256 r1 = x / r;
            return uint128(r < r1 ? r : r1);
        }
    }
}

