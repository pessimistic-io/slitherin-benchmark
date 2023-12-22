// SPDX-License-Identifier: MIT

/**

https://t.me/arbistellar
https://twitter.com/ArbiStellar
https://arbistellar.xyz/

*/

pragma solidity ^0.8.0;

import "./ERC721EnumerableUpgradeable.sol";
import "./ReentrancyGuardUpgradeable.sol";
import "./CountersUpgradeable.sol";
import "./PausableUpgradeable.sol";
import "./Initializable.sol";
import "./OwnableUpgradeable.sol";
import "./STLR.sol";

import "./RoyaltiesImpl.sol";
import "./LibPart.sol";
import "./LibRoyalties.sol";

contract NodesManagerUpgradeableV3 is
Initializable,
ERC721EnumerableUpgradeable,
PausableUpgradeable,
OwnableUpgradeable,
ReentrancyGuardUpgradeable,
RoyaltiesImpl
{
    using CountersUpgradeable for CountersUpgradeable.Counter;

    struct NodeEntity {
        uint256 id;
        string name;
        uint256 creationTime;
        uint256 lastProcessingTimestamp;
        uint24 rewardMulti;
        uint256 nodeValue;
        uint256 totalClaimed;
        uint8 counterCompound;
        bool exists;
    }

    struct NodeInfoEntity {
        NodeEntity tokenNode;
        uint256 id;
        uint256 pendingRewards;
        uint256 rewardPerDay;
        uint256 compoundDelay;
        uint256 pendingRewardsGross;
        uint256 rewardPerDayGross;
    }

    struct TierStorage {
        uint24 rewardMulti;
        uint256 amountLockedInTier;
        bool exists;
    }

    // reference to the $STLR contract
    STLR stlr;

    CountersUpgradeable.Counter private _nodeCounter;
    mapping(uint256 => NodeEntity) private _nodes;
    mapping(uint256 => TierStorage) private _tierTracking;
    uint256[] _tiersTracked;

    uint256 public rewardPerDay;
    uint256 public creationMinPrice;
    uint16 public compoundDelay;

    uint24[3] public tierLevel;
    uint8[3] public tierSlope;
    uint8[2] public compoundLevelUp;

    string private baseURI;
    uint256 private constant ONE_DAY = 86_400;
    uint256 public totalValueLocked;
    string public baseExtension;
    uint256 public startTime;

    // royalties
    bytes4 private constant _INTERFACE_ID_ERC2981 = 0x2a55205a;
    address public royaltiesAddress;
    address payable royaltiesAddressPayable;

    uint256 public totalValueGenerate;



    modifier checkPermissions(uint256 _nodeId) {
        address sender = _msgSender();
        require(nodeExists(_nodeId),
            "Node: This node doesn't exist"
        );
        require(
            isApprovedOrOwnerOfNode(sender, _nodeId),
            "Node: You do not have control over this node"
        );
        _;
    }

    modifier checkPermissionsMultiple(uint256[] memory _nodeIds) {
        address sender = _msgSender();
        for (uint256 i = 0; i < _nodeIds.length; i++) {
            require(
                nodeExists(_nodeIds[i]),
                "Node: This node doesn't exist"
            );
            require(
                isApprovedOrOwnerOfNode(sender, _nodeIds[i]),
                "Node: You do not control this node"
            );
        }
        _;
    }

    modifier verifyName(string memory nodeName) {
        require(
            bytes(nodeName).length > 1 && bytes(nodeName).length < 32,
            "Node: Incorrect name length, must be between 2 to 31"
        );
        _;
    }

    event Compound(
        address indexed account,
        uint256 indexed nodeId,
        uint256 amountToCompound
    );
    event Collect(
        address indexed account,
        uint256 indexed nodeId,
        uint256 rewardAmount
    );
    event CompoundAll(
        address indexed account,
        uint256[] indexed affectedNodes,
        uint256 amountToCompoundts
    );
    event CollectAll(
        address indexed account,
        uint256[] indexed affectedNodes,
        uint256 rewardAmount
    );
    event Create(
        address indexed account,
        uint256 indexed newStlrNodeId,
        uint256 amount
    );

    function initialize() external initializer
    {
        __ERC721_init("STELLAR_NODES", "STN");
        __Ownable_init();
        __ERC721Enumerable_init();
        __ReentrancyGuard_init();
        __Pausable_init();
    }

    function tokenURI(uint256 nodeId)
    public
    view
    virtual
    override
    returns (string memory)
    {
        NodeEntity storage node = _nodes[nodeId];

        uint256 level = getLevel(node.rewardMulti);
        string memory image = string(abi.encodePacked(baseURI, uint2str(level), baseExtension));
        string memory attributes = string(abi.encodePacked("\"attributes\":[{\"trait_type\":\"Level","\",\"value\":\"", uint2str(level),"\"},{\"trait_type\":\"amountToken","\",\"value\":\"", convert(node.nodeValue),"\"}]"));
        string memory json = base64(
            bytes(string(
                abi.encodePacked(
                    '{',
                    '"name": "', node.name, '"',
                    ', "edition":"', uint2str(getLevel(node.rewardMulti)), '"',
                    ', "image":"', image, '"',
                    ',',attributes,
                    '}'
                )
            ))
        );
        return string(abi.encodePacked('data:application/json;base64,', json));
    }

    function getLevel(uint256 multi) private view returns (uint256)
    {
        if (multi >= tierLevel[0] && multi < tierLevel[1]) {
            return 1;
        } else if (multi >= tierLevel[1] && multi < tierLevel[2]) {
            return 2;
        } else
            return 3;
    }

    function createNodeWithTokens(string memory nodeName, uint256 nodeValue)
    public payable whenNotPaused verifyName(nodeName)
    returns (uint256)
    {
        require(block.timestamp >= startTime, "Node: Node is not start");
        address sender = _msgSender();
        require(
            nodeValue * 10**18 >= creationMinPrice,
            "Node: Node value set below minimum"
        );
        require(
            isNameAvailable(sender, nodeName),
            "Nodes: Name not available"
        );
        require(
            stlr.balanceOf(sender) >= creationMinPrice,
            "Node: Balance too low for creation"
        );

        // Burn the tokens used to mint the NFT
        stlr.burn(sender, nodeValue * 10**18);

        // Increment the total number of tokens
        _nodeCounter.increment();

        uint256 newStlrNodeId = _nodeCounter.current();
        uint256 currentTime = block.timestamp;

        // Add this to the TVL
        totalValueLocked += nodeValue * 10**18;
        logTier(tierLevel[0], int256(nodeValue * 10**18));

        // Add node
        _nodes[newStlrNodeId] = NodeEntity({
        id: newStlrNodeId,
        name: nodeName,
        creationTime: currentTime,
        lastProcessingTimestamp: currentTime,
        rewardMulti: tierLevel[0],
        nodeValue: nodeValue * 10**18,
        totalClaimed: 0,
        counterCompound: 0,
        exists: true
        });

        // Assign the node to this account
        _mint(sender, newStlrNodeId);

        // Royalties fixed 7.5%
        setRoyalties(newStlrNodeId, royaltiesAddressPayable, 750);

        emit Create(sender, newStlrNodeId, nodeValue);

        return newStlrNodeId;
    }

    function levelUp(uint256 _nodeId)
    public
    payable
    checkPermissions(_nodeId)
    whenNotPaused
    {
        NodeEntity storage node = _nodes[_nodeId];
        require(
            isProcessable(node),
            "Node: Time limit for level up too short"
        );
        require(
            (node.counterCompound >= compoundLevelUp[0] && node.rewardMulti >= tierLevel[0] && node.rewardMulti < tierLevel[1])
            ||
            node.counterCompound >= compoundLevelUp[1] && node.rewardMulti >= tierLevel[1] && node.rewardMulti < tierLevel[2],
            "Node: Number of compound not respected"
        );
        uint256 amountToReward = calculateReward(node);
        if (node.rewardMulti >= tierLevel[0] && node.rewardMulti < tierLevel[1] && node.counterCompound >= compoundLevelUp[0]) {
            node.nodeValue += amountToReward;
            node.rewardMulti = tierLevel[1];
        } else if (node.rewardMulti >= tierLevel[1] && node.rewardMulti < tierLevel[2] && node.counterCompound >= compoundLevelUp[1]) {
            node.nodeValue += amountToReward;
            node.rewardMulti = tierLevel[2];
        }
        node.lastProcessingTimestamp = block.timestamp;
    }

    function collectReward(uint256 _nodeId)
    external payable nonReentrant checkPermissions(_nodeId) whenNotPaused
    {
        address account = _msgSender();
        uint256 amountToReward = _getNodeCollectRewards(_nodeId);
        _collectReward(amountToReward);
        totalValueGenerate += amountToReward;
        emit Collect(account, _nodeId, amountToReward);
    }

    function collectAll()
    external payable nonReentrant whenNotPaused
    {
        address account = _msgSender();
        uint256 rewardsTotal = 0;
        uint256[] memory nodesOwned = getNodeIdsOf(account);
        for (uint256 i = 0; i < nodesOwned.length; i++) {
            uint256 amountToReward = _getNodeCollectRewards(nodesOwned[i]);
            rewardsTotal += amountToReward;
        }
        _collectReward(rewardsTotal);

        totalValueGenerate += rewardsTotal;
        emit CollectAll(account, nodesOwned, rewardsTotal);
    }

    function compoundReward(uint256 _nodeId)
    public payable checkPermissions(_nodeId) whenNotPaused
    {
        address account = _msgSender();
        uint256 amountToCompound = _getNodeCompoundRewards(_nodeId);
        require(
            amountToCompound > 0,
            "Node: You must wait for the end of the compound delay period"
        );

        emit Compound(account, _nodeId, amountToCompound);
    }

    function compoundAll() external payable nonReentrant whenNotPaused {
        address account = _msgSender();
        uint256 amountsToCompound = 0;
        uint256[] memory nodesOwned = getNodeIdsOf(account);
        uint256[] memory nodesAffected = new uint256[](nodesOwned.length);

        for (uint256 i = 0; i < nodesOwned.length; i++) {
            uint256 amountToCompound = _getNodeCompoundRewards(
                nodesOwned[i]
            );
            if (amountToCompound > 0) {
                nodesAffected[i] = nodesOwned[i];
                amountsToCompound += amountToCompound;
            } else {
                delete nodesAffected[i];
            }
        }
        require(
            amountsToCompound > 0,
            "Node: No rewards to compound"
        );
        emit CompoundAll(account, nodesAffected, amountsToCompound);
    }

    function _getNodeCollectRewards(uint256 _nodeId)
    private
    returns (uint256)
    {
        NodeEntity storage node = _nodes[_nodeId];
        require(
            isProcessable(node),
            "Node: You must wait for the end of the compound delay period"
        );

        uint256 reward = calculateReward(node);
        node.totalClaimed += reward;
        logTier(node.rewardMulti, int256(node.nodeValue));
        node.counterCompound = 0;
        node.rewardMulti = tierLevel[0];
        node.lastProcessingTimestamp = block.timestamp;

        return reward;
    }

    function _getNodeCompoundRewards(uint256 _nodeId)
    private
    returns (uint256)
    {
        NodeEntity storage _node = _nodes[_nodeId];

        if (!isProcessable(_node)) {
            return 0;
        }

        uint256 reward = calculateReward(_node);
        if (reward > 0) {
            totalValueLocked += reward;

            _node.lastProcessingTimestamp = block.timestamp;
            _node.nodeValue += reward;
            _node.counterCompound += 1;
            _node.rewardMulti += increaseMultiplier(_node.rewardMulti);
            logTier(_node.rewardMulti, int256(_node.nodeValue));
        }
        return reward;
    }

    function _collectReward(uint256 amountToReward)
    private
    {
        require(
            amountToReward > 0,
            "Node: You have no pending rewards to claim"
        );
        address to = _msgSender();
        stlr.mint(to, (amountToReward));
    }

    function logTier(uint24 multi, int256 amount) private {
        TierStorage storage tierStorage = _tierTracking[multi];
        if (tierStorage.exists) {
            require(
                tierStorage.rewardMulti == multi,
                "Node: rewardMulti does not match in TierStorage"
            );
            uint256 amountLockedInTier = uint256(
                int256(tierStorage.amountLockedInTier) + amount
            );
            require(
                amountLockedInTier >= 0,
                "Node: amountLockedInTier cannot underflow"
            );
            tierStorage.amountLockedInTier = amountLockedInTier;
        } else {
            // Tier isn't registered exist, register it
            require(
                amount > 0,
                "Node: Fatal error while creating new TierStorage. Amount cannot be below zero"
            );
            _tierTracking[multi] = TierStorage({
            rewardMulti: multi,
            amountLockedInTier: uint256(amount),
            exists: true
            });
            _tiersTracked.push(multi);
        }
    }

    function increaseMultiplier(uint256 prevMulti)
    private view
    returns (uint24)
    {
        if (prevMulti >= tierLevel[2]) {
            return tierSlope[2];
        } else if (prevMulti >= tierLevel[1]) {
            return tierSlope[1];
        } else
            return tierSlope[0];
    }

    function getTieredRevenues(uint256 multi)
    private view
    returns (uint256) {
        if (multi >= tierLevel[2]) {
            // 2.1%
            return 22_263;
        } else if (multi >= tierLevel[1]) {
            // 1.3%
            return 15_046;
        } else
        // 1%
            return 11_573;

    }

    function isProcessable(NodeEntity memory _node)
    private view
    returns (bool)
    {
        return
        block.timestamp >= _node.lastProcessingTimestamp + compoundDelay;
    }

    function calculateReward(NodeEntity memory _node)
    private view
    returns (uint256)
    {
        return
        _calculateRewardsFromValue(
            _node.nodeValue,
            _node.rewardMulti,
            block.timestamp - _node.lastProcessingTimestamp
        );
    }

    function rewardPerDayFor(NodeEntity memory _node)
    private view
    returns (uint256)
    {
        return
        _calculateRewardsFromValue(
            _node.nodeValue,
            _node.rewardMulti,
            ONE_DAY
        );
    }

    function _calculateRewardsFromValue(uint256 _nodeValue, uint24 _rewardMulti, uint256 _timeRewards)
    private view returns (uint256)
    {
        uint256 decimalNodeValue = _nodeValue / 10**18;
        uint256 rewards = (_timeRewards * getTieredRevenues(_rewardMulti));
        uint256 multiplicationRewards = (rewards * _rewardMulti);
        return (multiplicationRewards * decimalNodeValue) * 100;
    }

    function nodeExists(uint256 _nodeId)
    private view returns (bool)
    {
        require(
            _nodeId > 0,
            "Node: Id 0 does not exist"
        );
        NodeEntity memory _node = _nodes[_nodeId];
        if (_node.exists) {
            return true;
        }
        return false;
    }

    function calculateTotalDailyEmission()
    external view
    returns (uint256)
    {
        uint256 dailyEmission = 0;
        for (uint256 i = 0; i < _tiersTracked.length; i++) {
            TierStorage memory tierStorage = _tierTracking[_tiersTracked[i]];
            dailyEmission += _calculateRewardsFromValue(
                tierStorage.amountLockedInTier,
                tierStorage.rewardMulti,
                ONE_DAY
            );
        }
        return dailyEmission;
    }

    function isNameAvailable(address account, string memory nodeName)
    public view
    returns (bool)
    {
        uint256[] memory nodesOwned = getNodeIdsOf(account);
        for (uint256 i = 0; i < nodesOwned.length; i++) {
            NodeEntity memory _node = _nodes[nodesOwned[i]];
            if (keccak256(bytes(_node.name)) == keccak256(bytes(nodeName))) {
                return false;
            }
        }
        return true;
    }

    function isApprovedOrOwnerOfNode(address account, uint256 _nodeId)
    public view
    returns (bool)
    {
        return _isApprovedOrOwner(account, _nodeId);
    }

    function getNodeIdsOf(address account)
    public view
    returns (uint256[] memory)
    {
        uint256 numberOfNodes = balanceOf(account);
        uint256[] memory _nodeIds = new uint256[](numberOfNodes);
        for (uint256 i = 0; i < numberOfNodes; i++) {
            uint256 _nodeId = tokenOfOwnerByIndex(account, i);
            require(
                nodeExists(_nodeId),
                "Node: This node doesn't exist"
            );
            _nodeIds[i] = _nodeId;
        }
        return _nodeIds;
    }

    function getNodesByIds(uint256[] memory _nodeIds)
    external view
    returns (NodeInfoEntity[] memory)
    {
        NodeInfoEntity[] memory _nodesInfo = new NodeInfoEntity[](
            _nodeIds.length
        );

        for (uint256 i = 0; i < _nodeIds.length; i++) {
            uint256 nodeId = _nodeIds[i];
            NodeEntity memory node = _nodes[nodeId];
            uint256 amountToReward = calculateReward(node);
            uint256 amountToRewardDaily = rewardPerDayFor(node);
            _nodesInfo[i] = NodeInfoEntity(
                node,
                nodeId,
                amountToReward,
                amountToRewardDaily,
                compoundDelay,
                0,
                0
            );
        }
        return _nodesInfo;
    }

    function setTokens(STLR addr) public onlyOwner {
        stlr = addr;
    }

    function setBaseExtension(string memory _newBaseExtension)
    public
    onlyOwner {
        baseExtension = _newBaseExtension;
    }

    function changeNodeMinPrice(uint256 _creationMinPrice) public onlyOwner {
        require(
            _creationMinPrice > 0,
            "Node: Minimum price to create a node must be above 0"
        );
        creationMinPrice = _creationMinPrice * 10**18;
    }

    function changeCompoundDelay(uint16 _compoundDelay) public onlyOwner {
        require(
            _compoundDelay > 0,
            "Node: compoundDelay must be greater than 0"
        );
        compoundDelay = _compoundDelay;
    }

    function changeTierSystem(
        uint24[3] memory _tierLevel,
        uint8[3] memory _tierSlope,
        uint8[2] memory _compoundLevelUp
    ) public onlyOwner {
        require(
            _tierLevel.length == 3,
            "Node: newTierLevels length has to be 3"
        );
        require(
            _tierSlope.length == 3,
            "Node: newTierSlopes length has to be 3"
        );
        require(
            _compoundLevelUp.length == 2,
            "Node: newCompoundLevelUp length has to be 2"
        );
        tierLevel = _tierLevel;
        tierSlope = _tierSlope;
        compoundLevelUp = _compoundLevelUp;
    }

    function setBaseUri(string memory _newUri) public onlyOwner
    {
        baseURI = _newUri;
    }

    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }

    function setStartTime(uint256 _newStartTime)
    public
    onlyOwner
    {
        startTime = _newStartTime;
    }

    function setAddressRoyalties (address _newRoyaltiesAddress)
    public
    onlyOwner
    {
        royaltiesAddressPayable = payable(_newRoyaltiesAddress);
    }

    function setRoyalties(uint tokenId, address payable royaltiesRecipientAddress, uint96 percentageBasisPoints)
    private
    {
        LibPart.Part[] memory royalties = new LibPart.Part[](1);
        royalties[0].value = percentageBasisPoints;
        royalties[0].account = royaltiesRecipientAddress;
        _saveRoyalties(tokenId, royalties);
    }

    function royaltyInfo(uint256 _tokenId, uint256 _salePrice)
    external
    view
    returns (address receiver, uint256 royaltyAmount)
    {
        LibPart.Part[] memory _royalties = royalties[_tokenId];
        if (_royalties.length > 0) {
            return (_royalties[0].account, (_salePrice * _royalties[0].value) / 10000);
        }
    }

    function supportsInterface(bytes4 interfaceId)
    public
    view
    virtual
    override(ERC721EnumerableUpgradeable)
    returns (bool)
    {
        if (interfaceId == LibRoyalties._INTERFACE_ID_ROYALTIES) {
            return true;
        }

        if (interfaceId == _INTERFACE_ID_ERC2981) {
            return true;
        }
        return super.supportsInterface(interfaceId);
    }

    // LIB
    string internal constant TABLE = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';

    function uint2str(uint _i) internal pure returns (string memory _uintAsString) {
        if (_i == 0) {
            return "0";
        }
        uint j = _i;
        uint len;
        while (j != 0) {
            len++;
            j /= 10;
        }
        bytes memory bstr = new bytes(len);
        uint k = len;
        while (_i != 0) {
            k = k-1;
            uint8 temp = (48 + uint8(_i - _i / 10 * 10));
            bytes1 b1 = bytes1(temp);
            bstr[k] = b1;
            _i /= 10;
        }
        return string(bstr);
    }

    function base64(bytes memory data) internal pure returns (string memory) {
        if (data.length == 0) return '';

        string memory table = TABLE;
        uint256 encodedLen = 4 * ((data.length + 2) / 3);
        string memory result = new string(encodedLen + 32);
        assembly {
            mstore(result, encodedLen)
            let tablePtr := add(table, 1)
            let dataPtr := data
            let endPtr := add(dataPtr, mload(data))
            let resultPtr := add(result, 32)
            for {} lt(dataPtr, endPtr) {}
            {
                dataPtr := add(dataPtr, 3)
                let input := mload(dataPtr)
                mstore(resultPtr, shl(248, mload(add(tablePtr, and(shr(18, input), 0x3F)))))
                resultPtr := add(resultPtr, 1)
                mstore(resultPtr, shl(248, mload(add(tablePtr, and(shr(12, input), 0x3F)))))
                resultPtr := add(resultPtr, 1)
                mstore(resultPtr, shl(248, mload(add(tablePtr, and(shr(6, input), 0x3F)))))
                resultPtr := add(resultPtr, 1)
                mstore(resultPtr, shl(248, mload(add(tablePtr, and(input, 0x3F)))))
                resultPtr := add(resultPtr, 1)
            }
            switch mod(mload(data), 3)
            case 1 {mstore(sub(resultPtr, 2), shl(240, 0x3d3d))}
            case 2 {mstore(sub(resultPtr, 1), shl(248, 0x3d))}
        }
        return result;
    }

    function convert(uint256 amountInWei) internal view returns (string memory) {
        uint256 amountInEther = amountInWei / 1 ether;
        uint256 decimalPart = (amountInWei % 1 ether) / (1 ether / 1e6);
        string memory result = string(abi.encodePacked(toString(amountInEther), ".", toString(decimalPart)));
        return result;
    }

    function toString(uint256 value) private view returns (string memory) {
        if (value == 0) {
            return "0";
        }
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        return string(buffer);
    }
}

