// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;
import "./Ownable.sol";
import "./Address.sol";
import "./VerifySignature.sol";
import "./Yeyeverse.sol";
import "./YeyeTrait.sol";
import "./YeyeVault.sol";
import "./YeyeTicket.sol";

contract RedeemTicket is Ownable {
    /* =============================================================
    * STATES
    ============================================================= */

    struct GetResult {
        uint256 id;
        uint256 price;
    }
    struct SetResult {
        uint256 id;
        uint256 supply;
        uint256 price;
    }
    struct Grade {
        bool exist;
        bool freeChance;
        uint256 price;
    }
    struct SetGrade {
        uint256 grade;
        bool freeChance;
        uint256 price;
    }

    // Base NFT ID
    uint256 public baseID;

    // grades
    mapping(uint256 => Grade) public grades;
    uint256 public freeLimit;

    // sale state
    uint256 private closedIn;
    bool public paused;

    // withdraw address
    address payable immutable public withdrawAddress;

    // stores ticket NFT Contract Address
    YeyeTicket public ticketContract;
    // stores base NFT Contract Address
    Yeyeverse public baseContract;
    // stores trait NFT Contract Address
    YeyeTrait public traitContract;
    // stores vault NFT Contract Address
    YeyeVault public vaultContract;

    /* =============================================================
    * CONSTRUCTOR
    ============================================================= */

    constructor(
        address _ticketAddress,
        address _baseAddress,
        address _traitAddress,
        address _vaultAddress,
        address payable _withdrawAddress
    ) {
        setTicketContract(_ticketAddress);
        setBaseContract(_baseAddress);
        setTraitContract(_traitAddress);
        setVaultContract(_vaultAddress);
        withdrawAddress = _withdrawAddress;

        setBase(0);
        setFreeLimit(3);
    }

    /* =============================================================
    * MODIFIER
    ============================================================= */

    modifier isNotClosed() {
        require(block.timestamp <= closedIn, "Mint is over");
        _;
    }
    modifier isClosed() {
        require(block.timestamp > closedIn, "Mint is not over yet");
        _;
    }
    modifier isPaused() {
        require(paused, "Mint is not paused");
        _;
    }
    modifier isNotPaused() {
        require(!paused, "Mint is paused");
        _;
    }

    /* =============================================================
    * SETTERS
    ============================================================= */

    /*
     * @dev set list of base NFT IDs to sell
     */
    function setBase(uint256 _id) public onlyOwner {
        (bool exist, bool redeemable, bool equipable) = baseContract.tokenCheck(_id);
        require(exist && !redeemable && equipable, string(abi.encodePacked("REVEAL: Base with ID: ", Strings.toString(_id), " doesn't exist/invalid type")));
        baseID = _id;
    }

    /*
     * @dev set list of ticket IDs
     */
    function setGrade(SetGrade[] calldata _data) public onlyOwner {
        for (uint256 i = 0; i < _data.length; i++) {
            grades[_data[i].grade].exist = true;
            grades[_data[i].grade].price = _data[i].price;
            grades[_data[i].grade].freeChance = _data[i].freeChance;
        }
    }

    function unsetGrade(uint[] calldata _grades) public onlyOwner {
        for (uint256 i = 0; i < _grades.length; i++) {
            grades[_grades[i]].exist = false;
        }
    }

    /*
     * @dev set free chance
     */
    function setFreeLimit(uint256 _limit) public onlyOwner {
        freeLimit = _limit;
    }

    /*
     * @dev set ticket contract address
     */
    function setTicketContract(address _newAddress) public onlyOwner {
        require(_newAddress != address(0), "REVEAL: Invalid Address");
        ticketContract = YeyeTicket(_newAddress);
    }

    /*
     * @dev set base contract address
     */
    function setBaseContract(address _newAddress) public onlyOwner {
        require(_newAddress != address(0), "REVEAL: Invalid Address");
        baseContract = Yeyeverse(_newAddress);
    }

    /*
     * @dev set trait contract address
     */
    function setTraitContract(address _newAddress) public onlyOwner {
        require(_newAddress != address(0), "REVEAL: Invalid Address");
        traitContract = YeyeTrait(_newAddress);
    }

    /*
     * @dev set vault contract address
     */
    function setVaultContract(address _newAddress) public onlyOwner {
        require(_newAddress != address(0), "REVEAL: Invalid Address");
        vaultContract = YeyeVault(_newAddress);
    }

    /* =============================================================
    * GETTERS
    ============================================================= */

    /*
    * @dev get time left of the current sale
    */
    function getTimeLeft() public view returns (uint _timeLeft) {
        _timeLeft = closedIn - block.timestamp;
    }

    /*
     * @dev get count of sender's ticket
     */
    function getTicketCount() public view returns (uint256 count) {
        count = ticketContract.balanceOf(_msgSender());
    }

    /*
     * @dev check sender's ticket
     */
    function checkTicketOwner(uint256 ticketID) public view returns (bool owner) {
        owner = ticketContract.ownerOf(ticketID) == _msgSender();
    }

    /*
     * @dev get trait IDs
     */
    function getTraitIds(YeyeTrait.TraitKey[] calldata _traits) private pure returns (uint256[] memory) {
        uint256[] memory ids = new uint256[](_traits.length);
        for (uint256 i = 0; i < ids.length; i++) {
            ids[i] = _traits[i].id;
        }
        return ids;
    }

    /* =============================================================
    * MAIN FUNCTION
    ============================================================= */

    /*
     * @dev Start new Mint Sale
     * Param :
     * - _base      = Base NFT ID
     * - _freeLimit = Free traits limit
     * - duration   = Duration of the sale (in hours)
     */
    function startNew(uint256 duration) public onlyOwner isClosed {
        paused = false;
        closedIn = block.timestamp + (duration * 1 hours);
    }

    /*
     * @dev pause mint
     */
    function pause() public onlyOwner isNotClosed isNotPaused {
        paused = true;
    }
    /*
     * @dev unpause mint
     */
    function unpause() public onlyOwner isNotClosed isPaused {
        paused = false;
    }

    /*
    * @dev add more time to extend sale duration
    */
    function addTime(uint hour) public onlyOwner {
        closedIn = block.timestamp + (hour * 1 hours);
    }

    /*
     * @dev force close mint
     */
    function forceClose() public onlyOwner isNotClosed {
        paused = false;
        closedIn = 0;
    }

    /*
     * @dev mint and equip NFT
     */
    function mint(uint256 _newId, YeyeTrait.TraitKey[] calldata _traits, uint256 _total, uint ticketID, bytes calldata sig) public payable isNotClosed isNotPaused {
        require(VerifySignature.redeem(0, _newId, baseID, _traits, _total, ticketID, _msgSender(), sig), "Invalid Parameter");
        require(_traits.length > 0, "Please select at least one trait");
        verifyPrice(_traits, _total);
        checkTrait(_traits);
        require(msg.value >= _total, "REVEAL: Not enough ether");
        burnTicket(ticketID);
        equipYeye(_newId, baseID, getTraitIds(_traits));
        baseContract.mint(_msgSender(), _newId, 1, "0x00");
    }

    /*
     * @dev equip function, create blueprint then store used NFT to vault
     */
    function equipYeye(uint256 _newId, uint256 _base, uint256[] memory _traits) private {
        Yeyeverse.YeyeBlueprint memory blueprint = Yeyeverse.YeyeBlueprint(
            true,
            _base,
            _traits
        );
        vaultContract.storeBase(_msgSender(), _base);
        vaultContract.storeTraits(_msgSender(), _traits);
        baseContract.registerEquipped(_newId, blueprint);
    }

    /*
     * @dev burn one ticket for mint proccess
     */
    function burnTicket(uint ticketID) private {
        require(getTicketCount() > 0, "You don't have any ticket");
        ticketContract.factoryBurn(ticketID, _msgSender());
    }

    /*
     * @dev function to check if ticket is the right type NFT
     */
    function checkTrait(YeyeTrait.TraitKey[] calldata _traits) private view {
        for (uint256 i = 0; i < _traits.length; i++) {
            require(
                traitContract.traitCheck(_traits[i].id, _traits[i].grade, _traits[i].key), 
                string(abi.encodePacked("REVEAL: Trait with ID: ", Strings.toString(_traits[i].id), " doesn't exist"))
            );
        }
    }

    /*
     * @dev verify price
     */
    function verifyPrice(YeyeTrait.TraitKey[] calldata _traits, uint256 _total) private view {
        uint256 total = calcTotal(_traits);
        uint256 discount = calcDiscount(_traits);

        require(_total == (total - discount), "Invalid price");
    }

    /*
     * @dev calculate total price
     */
    function calcTotal(YeyeTrait.TraitKey[] calldata _traits) private view returns (uint256 total) {
        for (uint256 i = 0; i < _traits.length; i++) {
            Grade memory grade = grades[_traits[i].grade];
            require(grade.exist, "Legendary trait unavailable");
            total += grade.price;
        }
    }

    /*
     * @dev calculate discount
     */
    function calcDiscount(YeyeTrait.TraitKey[] calldata _traits) private view returns (uint256 discount) {
        uint256 counter = 0;
        for (uint256 i = 0; i < _traits.length; i++) {
            Grade memory grade = grades[_traits[i].grade];
            require(grade.exist, "Legendary trait unavailable");
            if (!grade.freeChance) continue;
            counter++;
            discount += grade.price;
            if (counter >= freeLimit) break;
        }
    }

    /* =============================================================
    * OWNER AREA
    ============================================================= */

    /*
     * @dev Transfer funds to withdraw address
     */
    function withdrawAll() public onlyOwner {
        require(withdrawAddress != address(0), "Cannot withdraw to Address Zero");
        uint256 balance = address(this).balance;
        require(balance > 0, "there is nothing to withdraw");
        Address.sendValue(withdrawAddress, balance);
    }
}

