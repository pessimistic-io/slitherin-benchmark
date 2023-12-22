// SPDX-License-Identifier: UNLICENSED
// Author: @stevieraykatz
// https://github.com/coinlander/Coinlander

pragma solidity ^0.8.10;

import "./ERC721Enumerable.sol";
import "./AccessControl.sol";
import "./ReentrancyGuard.sol";
import "./ISeekers.sol";
import "./ICloak.sol";

contract Seekers is ERC721Enumerable, ISeekers, AccessControl, ReentrancyGuard {
    // Access control setup
    bytes32 constant KEEPERS_ROLE = keccak256("KEEPERS_ROLE"); // Role for Keepers
    bytes32 constant GAME_ROLE = keccak256("GAME_ROLE"); // Role for approved Coinlander game contracts

    // Counter inits
    uint256 private _summonSeekerId = 0; // Sale id tracker
    uint256 private _birthSeekerId = 0; // Internal id tracker

    // Minting params
    uint256 public constant MAXSEEKERS = 11111;
    uint256 public currentBuyableSeekers = 0;
    uint256 public currentPrice = 0;
    uint256 constant KEEPERSEEKERS = 111; // Number of Seekers that Keepers can mint for themselves
    uint256 private keepersSeekersMinted = 0;
    uint256 constant MAXMINTABLE = 10; // Max seekers that can be purchased in one tx

    // Seeker release schedule
    // Activation for each will be called externally by the season 1 Coinlander contract
    uint256 constant FIRSTMINT = 5000;
    bool public firstMintActive = false;
    uint256 constant FIRSTMINTPRICE = 0.05 ether;
    uint256 public constant SECONDMINT = 3333;
    bool public secondMintActive = false;
    uint256 constant SECONDMINTPRICE = 0.08 ether;
    uint256 constant THIRDMINT = 220; // bulk release at third mint thresh
    uint256 constant THIRDMINT_INCR = 4; // additional release at each seizure after third mint thresh
    uint256 constant THIRDMINT_TOTAL = 1556; // total number of seekers released via third mint (220 + 4*334)
    bool public thirdMintActive = false;
    uint256 constant THIRDMINTPRICE = 0.1 ether;

    // Game params
    bool public evilsOnly = false;
    bool public goodsOnly = false;

    // This adds 1 because we are special casing the winner_id and setting it to 1
    uint256 private constant INTERNALIDOFFSET =
        FIRSTMINT + SECONDMINT + THIRDMINT_TOTAL + KEEPERSEEKERS + 1;

    // On-chain game parameters
    bool public released = false;
    bool public cloakingAvailable = false;
    uint16 public constant MAXPOWER = 1024; // 32x32 pixel grid
    uint16 public constant POWERPERHOUR = 1; // 1 power unit for every hour held
    uint16 public constant SUMMONSEEKERPOWERSTART = 3;
    uint16 public constant BIRTHSEEKERPOWERSTART = 5;
    uint16 public constant DETHSCALEREROLLCOST = 1;
    mapping(uint256 => bool) isSeekerCloaked;

    struct Attributes {
        string alignment;
        bool bornFromCoin;
        uint8 alpha;
        uint8 beta;
        uint8 delta;
        uint8 gamma;
        uint16 power;
        uint16 dethscales;
        address clan;
    }

    mapping(uint256 => Attributes) attributesBySeekerId;

    ICloak cloak;

    // Off-chain metadata
    string private _contractURI = "https://api.coinlander.one/meta/seekers";
    string private _baseTokenURI = "https://api.coinlander.one/meta/seekers/";

    // Alignment
    string[] private alignments = [
        "Lawful Good",
        "Neutral Good",
        "Chaotic Good",
        "Lawful Neutral",
        "True Neutral",
        "Chaotic Neutral",
        "Lawful Evil",
        "Neutral Evil",
        "Chaotic Evil"
    ];

    constructor(address CloakLibAddr) ERC721("Coinlander: Seekers", "SEEKERS") {
        // Give the Keeper deploying this contract the Keeper role and set them as admin
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(KEEPERS_ROLE, msg.sender);
        _setRoleAdmin(KEEPERS_ROLE, DEFAULT_ADMIN_ROLE);

        // Attach Seeker contract to Cloak lib
        cloak = ICloak(CloakLibAddr);

        // Set aside ID 1 for winner
        _summonSeekerId += 1;
        _safeMint(msg.sender, _summonSeekerId);
        attributesBySeekerId[1].bornFromCoin = true;

        _birthSeekerId = INTERNALIDOFFSET;
    }

    //////////////////////////////////////////////////////////////////////////////////////////////////
    //                                                                                              //
    //                                  MINTING AND SUCH                                            //
    //                                                                                              //
    //////////////////////////////////////////////////////////////////////////////////////////////////

    function summonSeeker(uint256 summonCount) external payable nonReentrant {
        require(summonCount > 0 && summonCount <= MAXMINTABLE, "E-001-001");
        require(msg.value >= (currentPrice * summonCount), "E-001-002");
        require(
            (_summonSeekerId + summonCount) <= currentBuyableSeekers,
            "E-001-003"
        );

        for (uint256 i = 0; i < summonCount; i++) {
            _summonSeekerId += 1;
            _mintSeeker(
                msg.sender,
                _summonSeekerId,
                false,
                SUMMONSEEKERPOWERSTART
            );
        }
    }

    function birthSeeker(address to, uint32 holdTime)
        external
        onlyGame
        returns (uint256)
    {
        require(_birthSeekerId < MAXSEEKERS, "E-001-003");
        _birthSeekerId += 1;
        uint16 calculatedPower = _getPowerFromTime(holdTime) +
            BIRTHSEEKERPOWERSTART;
        // Ensure we dont assign more than max power to a seeker
        uint16 birthPower = (calculatedPower > MAXPOWER)
            ? MAXPOWER
            : calculatedPower;
        _mintSeeker(to, _birthSeekerId, true, birthPower);
        return (_birthSeekerId);
    }

    function keepersSummonSeeker(uint256 summonCount)
        external
        nonReentrant
        onlyKeepers
    {
        require(
            (keepersSeekersMinted + summonCount) <= KEEPERSEEKERS,
            "E-001-004"
        );
        keepersSeekersMinted += summonCount;

        for (uint256 i = 0; i < summonCount; i++) {
            _summonSeekerId += 1;
            _mintSeeker(
                msg.sender,
                _summonSeekerId,
                false,
                SUMMONSEEKERPOWERSTART
            );
        }
    }

    function _mintSeeker(
        address to,
        uint256 id,
        bool bornFromCoin,
        uint16 startPower
    ) internal {
        // Initialize all attributes to "hidden" values
        Attributes memory cloakedAttributes = Attributes(
            "",
            bornFromCoin,
            0,
            0,
            0,
            0,
            startPower,
            uint16(0),
            address(0)
        );

        attributesBySeekerId[id] = cloakedAttributes;

        isSeekerCloaked[id] = false; // All Seekers begin uncloaked

        _safeMint(to, id);
    }

    //////////////////////////////////////////////////////////////////////////////////////////////////
    //                                                                                              //
    //                             EXTERNALLY CALLABLE GAME EVENTS                                  //
    //                                                                                              //
    //////////////////////////////////////////////////////////////////////////////////////////////////

    function activateFirstMint() external onlyGame {
        require(firstMintActive == false, "E-001-005");
        firstMintActive = true;
        emit FirstMintActivated();
        currentBuyableSeekers += (FIRSTMINT + KEEPERSEEKERS);
        currentPrice = FIRSTMINTPRICE;
    }

    function activateSecondMint() external onlyGame {
        require(secondMintActive == false, "E-001-006");
        secondMintActive = true;
        evilsOnly = true;
        emit SecondMintActivated();
        currentBuyableSeekers += SECONDMINT;
        currentPrice = SECONDMINTPRICE;
    }

    function activateThirdMint() external onlyGame {
        require(thirdMintActive == false, "E-001-007");
        thirdMintActive = true;
        evilsOnly = false;
        goodsOnly = true;
        emit ThirdMintActivated();
        currentBuyableSeekers += THIRDMINT;
        currentPrice = THIRDMINTPRICE;
    }

    function seizureMintIncrement() external onlyGame {
        currentBuyableSeekers += THIRDMINT_INCR;
    }

    function endGoodsOnly() external onlyGame {
        goodsOnly = false;
    }

    function performCloakingCeremony() external onlyGame {
        cloakingAvailable = true;
        emit CloakingAvailable();
    }

    function sendWinnerSeeker(address winner) external onlyGame {
        require(released == false, "E-001-008");
        released = true;
        _setWinnerSeekerAttributes(1);
        _safeTransfer(ownerOf(1), winner, 1, "0x0");
    }

    //////////////////////////////////////////////////////////////////////////////////////////////////
    //                                                                                              //
    //                           EXTERNALLY CALLABLE PLAYER ACTIONS                                 //
    //                                                                                              //
    //////////////////////////////////////////////////////////////////////////////////////////////////

    function cloakSeeker(uint256 id) external {
        require(cloakingAvailable, "E-001-009");
        require(msg.sender == ownerOf(id), "E-001-010");
        require(!isSeekerCloaked[id], "E-001-011");

        string memory _alignment = _getAlignment();

        uint8[4] memory _APs = _getAP(id);

        isSeekerCloaked[id] = true; // Cloaks the Seeker permanently

        Attributes memory revealedAttributes = Attributes(
            _alignment, // Sets the alignment
            attributesBySeekerId[id].bornFromCoin, // Dont change how the Seeker was created
            _APs[0], // Alpha
            _APs[1], // Beta
            _APs[2], // Detla
            _APs[3], // Gamma
            attributesBySeekerId[id].power,
            uint16(0),
            attributesBySeekerId[id].clan
        );
        attributesBySeekerId[id] = revealedAttributes;

        uint16 _dethscales = _getDethscales(id, false);
        attributesBySeekerId[id].dethscales = _dethscales;

        emit SeekerCloaked(id);
    }

    function rerollDethscales(uint256 id) external {
        require(cloakingAvailable, "E-001-009");
        require(msg.sender == ownerOf(id), "E-001-010");
        require(isSeekerCloaked[id], "E-001-012");

        _burnPower(id, DETHSCALEREROLLCOST);
        attributesBySeekerId[id].dethscales = _getDethscales(id, true);

        emit DethscalesRerolled(id);
    }

    function addPower(uint256 id, uint256 powerToAdd) external onlyGame {
        require(ownerOf(id) != address(0), "E-001-014");
        require(powerToAdd > 0, "E-001-015");
        uint16 _power = attributesBySeekerId[id].power;
        if ((_power + powerToAdd) > MAXPOWER) {
            attributesBySeekerId[id].power = MAXPOWER;
        } else {
            attributesBySeekerId[id].power += uint16(powerToAdd);
        }
        emit PowerAdded(id, powerToAdd, attributesBySeekerId[id].power);
    }

    function burnPower(uint256 id, uint16 powerToBurn) external onlyGame {
        require(ownerOf(id) != address(0), "E-001-014");

        _burnPower(id, powerToBurn);
    }

    function _burnPower(uint256 id, uint16 powerToBurn) internal {
        require(powerToBurn <= attributesBySeekerId[id].power, "E-001-021");
        attributesBySeekerId[id].power -= powerToBurn;

        emit PowerBurned(id, powerToBurn, attributesBySeekerId[id].power);
    }

    function declareForClan(uint256 id, address clanAddress) external {
        require(msg.sender == ownerOf(id), "E-001-010");
        require(clanAddress == address(clanAddress), "E-001-016");

        attributesBySeekerId[id].clan = clanAddress;
        emit SeekerDeclaredToClan(id, clanAddress);
    }

    //////////////////////////////////////////////////////////////////////////////////////////////////
    //                                                                                              //
    //                                  INTERNAL ATTRIBUTES AND METADATA                            //
    //                                                                                              //
    //////////////////////////////////////////////////////////////////////////////////////////////////

    function _baseURI() internal view override returns (string memory) {
        return _baseTokenURI;
    }

    function _getAlignment() internal view returns (string memory) {
        if (goodsOnly) {
            string[] memory goodAlignments = new string[](3);
            goodAlignments[0] = alignments[0];
            goodAlignments[1] = alignments[1];
            goodAlignments[2] = alignments[2];
            return _pluck(3, goodAlignments);
        }
        if (evilsOnly) {
            string[] memory evilAlignments = new string[](3);
            evilAlignments[0] = alignments[6];
            evilAlignments[1] = alignments[7];
            evilAlignments[2] = alignments[8];
            return _pluck(3, evilAlignments);
        }
        return _pluck(alignments.length, alignments);
    }

    // Alignment axes are defined as a tuple which describes where on the 3x3 square the alignment lands
    // Good -> Evil :: 0 -> 2
    // Lawful -> Chaotic :: 0 -> 2
    function _getAlignmentAxes(uint256 id)
        internal
        view
        returns (uint256, uint256)
    {
        string memory seekerAlignment = attributesBySeekerId[id].alignment;
        string memory _alignment;
        for (uint256 i = 0; i < alignments.length; i++) {
            _alignment = alignments[i];
            if (
                keccak256(bytes(seekerAlignment)) ==
                keccak256(bytes(_alignment))
            ) {
                return ((i / 3), (i % 3));
            }
        }
        return (0, 0); // Default if alignment not set
    }

    function _getAP(uint256 id) internal view returns (uint8[4] memory) {
        uint256 minSingle = 10;
        uint256 maxSingle = 23;
        uint8 minSum = 50;

        // Those born from the Coin are deterministically stronger
        if (attributesBySeekerId[id].bornFromCoin) {
            minSingle = 15;
            maxSingle = 25;
        }

        // Determine 4 random attribute points
        uint256 rangeSingle = maxSingle - minSingle + 1;
        uint8 ap1 = uint8(minSingle + _getRandomNumber(rangeSingle, id+1));
        uint8 ap2 = uint8(minSingle + _getRandomNumber(rangeSingle, id+2));
        uint8 ap3 = uint8(minSingle + _getRandomNumber(rangeSingle, id+3));
        uint8 ap4 = uint8(minSingle + _getRandomNumber(rangeSingle, id+4));

        // // Set power floor
        uint8 sum = ap1 + ap2 + ap3 + ap4;
        uint8[4] memory aps = [ap1, ap2, ap3, ap4];
        if (sum < minSum) {
            uint8 diff = minSum - sum;
            uint8 idx = _getMinIdx(aps);
            aps[idx] += diff;
        }

        // Shuffle them
        for (uint256 i = 0; i < aps.length; i++) {
            uint256 n = i +
                (uint256(keccak256(abi.encodePacked(block.timestamp))) %
                    (aps.length - i));
            uint8 temp = aps[n];
            aps[n] = aps[i];
            aps[i] = temp;
        }

        return aps;
    }

    function _getDethscales(uint256 _id, bool reroll)
        internal
        view
        returns (uint16)
    {
        // Set fill density based on alignment
        (uint256 x, ) = _getAlignmentAxes(_id); // Only need good/evil axis
        uint16 minDethscales;
        uint16 maxDethscales;
        if (x == 1) {
            minDethscales = 7; // Neutral case
            maxDethscales = 12;
        } else {
            minDethscales = 4; // Good and Evil cases
            maxDethscales = 8;
        }
        uint16 rand = uint16(_getRandomNumber(2**16, _id));
        uint16 _dethscales = cloak.getDethscales(
            minDethscales,
            maxDethscales,
            attributesBySeekerId[_id].dethscales,
            rand
        );
        uint16 rarityFlip = uint16(_getRandomNumber(100, rand));

        if (x == 2) {
            if (rarityFlip < 5 && !reroll) {
                // dont allow rarity flip on reroll
                return ~_dethscales; // invert for rare evil
            } else {
                return _dethscales; // dont invert for evil
            }
        } else if (x == 0) {
            if (rarityFlip < 5 && !reroll) {
                // dont allow rarity flip on reroll
                return _dethscales; // dont invert for rare good
            } else {
                return ~_dethscales; // invert for good
            }
        } else {
            return _dethscales;
        }
    }

    function _setWinnerSeekerAttributes(uint256 id) internal {
        isSeekerCloaked[id] = true; // Cloaks the Seeker permanently
        Attributes memory winningAttributes = Attributes(
            "True Neutral",
            true,
            25, // Alpha
            25, // Beta
            25, // Detla
            25, // Gamma
            MAXPOWER, // Power
            uint16(0), // Dethscales
            attributesBySeekerId[id].clan
        );
        attributesBySeekerId[id] = winningAttributes;
        emit SeekerCloaked(id);
    }

    //////////////////////////////////////////////////////////////////////////////////////////////////
    //                                                                                              //
    //                                  EXTERNAL ATTRIBUTES AND METADATA                            //
    //                                                                                              //
    //////////////////////////////////////////////////////////////////////////////////////////////////

    function contractURI() public view returns (string memory) {
        return _contractURI;
    }

    function getOriginById(uint256 id) external view returns (bool) {
        return attributesBySeekerId[id].bornFromCoin;
    }

    function getAlignmentById(uint256 id)
        external
        view
        returns (string memory)
    {
        string memory _alignment = attributesBySeekerId[id].alignment;
        return _alignment;
    }

    function getApById(uint256 id) external view returns (uint8[4] memory) {
        uint8[4] memory _aps = [
            attributesBySeekerId[id].alpha,
            attributesBySeekerId[id].beta,
            attributesBySeekerId[id].gamma,
            attributesBySeekerId[id].delta
        ];
        return _aps;
    }

    function getPowerById(uint256 id) external view returns (uint16) {
        return attributesBySeekerId[id].power;
    }

    function getClanById(uint256 id) external view returns (address) {
        return attributesBySeekerId[id].clan;
    }

    function getDethscalesById(uint256 id) external view returns (uint16) {
        return attributesBySeekerId[id].dethscales;
    }

    function getCloakStatusById(uint256 id) external view returns (bool) {
        return isSeekerCloaked[id];
    }

    function getFullCloak(uint256 id)
        external
        view
        returns (uint32[32] memory)
    {
        require(isSeekerCloaked[id], "E-001-012");
        uint16 _dethscales = attributesBySeekerId[id].dethscales;

        // Set noise based on alignment
        (, uint256 y) = _getAlignmentAxes(id); // Only need lawful/chaotic axis
        uint16 minNoiseBits;
        uint16 maxNoiseBits;
        if (y == 0) {
            // Lawful
            minNoiseBits = 0;
            maxNoiseBits = 16;
        }
        if (y == 1) {
            // Neutral
            minNoiseBits = 16;
            maxNoiseBits = 32;
        } else {
            // Chaotic
            minNoiseBits = 32;
            maxNoiseBits = 96;
        }

        return cloak.getFullCloak(minNoiseBits, maxNoiseBits,_dethscales);
    }

    //////////////////////////////////////////////////////////////////////////////////////////////////
    //                                                                                              //
    //                                  PSEUDORANDOMNESS & MAFS                                     //
    //                                                                                              //
    //////////////////////////////////////////////////////////////////////////////////////////////////

    // Thanks Manny - entropy is a bitch
    function _getRandomNumber(uint256 mod, uint256 r)
        private
        view
        returns (uint256)
    {
        uint256 random = uint256(
            keccak256(
                abi.encodePacked(
                    blockhash(block.number - 1),
                    block.timestamp,
                    msg.sender,
                    mod,
                    r
                )
            )
        );

        return random % mod;
    }

    function _pluck(uint256 mod, string[] memory sourceArray)
        internal
        view
        returns (string memory)
    {
        uint256 rand = _getRandomNumber(mod, 0);
        string memory output = sourceArray[rand % sourceArray.length];
        return output;
    }

    function _getMinIdx(uint8[4] memory vals) internal pure returns (uint8) {
        uint8 minIdx;
        for (uint8 i; i < 4; i++) {
            if (vals[i] < vals[minIdx]) {
                minIdx = i;
            }
        }
        return minIdx;
    }

    function _getPowerFromTime(uint32 time) internal pure returns (uint16) {
        // convert time to hours
        uint32 timeHours = time / (1 hours);
        return uint16(POWERPERHOUR * timeHours);
    }

    //////////////////////////////////////////////////////////////////////////////////////////////////
    //                                                                                              //
    //                                ACCESS CONTROL/PERMISSIONS                                    //
    //                                                                                              //
    //////////////////////////////////////////////////////////////////////////////////////////////////

    modifier onlyGame() {
        require(hasRole(GAME_ROLE, msg.sender), "E-001-017");
        _;
    }

    modifier onlyKeepers() {
        require(hasRole(KEEPERS_ROLE, msg.sender), "E-001-018");
        _;
    }

    function ownerWithdraw() external payable onlyKeepers {
        uint256 balance = address(this).balance;
        payable(msg.sender).transfer(balance);
    }

    function addGameContract(address gameContract) public onlyKeepers {
        grantRole(GAME_ROLE, gameContract);
    }

    function addKeeper(address newKeeper) public onlyKeepers {
        grantRole(KEEPERS_ROLE, newKeeper);
    }

    function setContractURI(string calldata newContractURI)
        external
        onlyKeepers
    {
        _contractURI = newContractURI;
    }

    function setBaseURI(string memory baseTokenURI) public onlyKeepers {
        _baseTokenURI = baseTokenURI;
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(IERC165, ERC721Enumerable, AccessControl)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    receive() external payable {
        revert("E-001-020");
    }
}

