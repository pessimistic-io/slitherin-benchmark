import "./AccessControl.sol";

// Dev Note: collapse these down into composable interfaces?
interface IAttribute {
  function attribute(uint256 characterId) external view returns (uint256);

  function adjustAttribute(uint256 newAttribute, uint256 characterId) external;

  function name() external view returns (string memory);

  function getURI() external view returns (uint256);
}

// Generics pattern? Right now having these general shapes that
// apply to both ITrait and IAttribute is clunky, but the string vs uint difference
// means we can't really collapse these into a single interface, think through a better pattern
interface ITrait {
  function trait(uint256 characterId) external view returns (string memory);

  function adjustTrait(string memory newTrait, uint256 characterId) external;

  function name() external view returns (string memory);

  // What are the use cases where we need this on the trait interface?
  // Are there other things we need for this interface?
  function getURI() external view returns (uint256);
}

contract Attributes is AccessControl {
  // Attributes Variables

  // Array representation of all attributes
  uint256 private _attributeCount;
  mapping(uint256 => IAttribute) private _attributesIndex;
  // Mapping from the "name" of the attribute to the "property" of the attribute.
  mapping(string => IAttribute) private _attributesMap;
  // Mapping from the "name" of the attribute to whether the attribute already exists on this character.
  mapping(string => bool) private _attributesAdded;

  bytes32 public constant ATTRIBUTE_ADDER = keccak256("ATTRIBUTE_ADDER");
  bytes32 public constant TRAIT_ADDER = keccak256("TRAIT_ADDER");

  // Note: Can we reduce these redundant mappings? There has to be a better way to store/access this information or something lighter.
  // What about a mapping from string to uint256 or something, that should be less storage, although it's two reads.

  // Array representation of all traits
  uint256 private _traitCount;

  // Philosophy: What is the actual difference between a trait and an attribute? Can we just store these as a single thing?

  // We may want this to be enum, how are we accessing this?
  mapping(uint256 => ITrait) private _traitsIndex;
  // Mapping from the "name" of the trait to the "property" of the trait.
  mapping(string => ITrait) private _traitsMap;
  // Mapping from the "name" of the attribute to whether the trait already exists on this character.
  mapping(string => bool) private _traitsAdded;

  /**
   * @dev
   */
  function attachTrait(ITrait trait) external {
    require(
      hasRole(TRAIT_ADDER, msg.sender),
      "Caller is not a valid attibute adder"
    );
    require(
      _traitsAdded[trait.name()],
      "Attribute already exists on character"
    );
    _traitsAdded[trait.name()] = true;
    _traitsMap[trait.name()] = trait;
    _traitsIndex[_traitCount] = trait;
    _traitCount += 1;
  }

  /**
   * @dev
   */
  function attachAttribute(IAttribute attribute) external {
    require(
      hasRole(TRAIT_ADDER, msg.sender),
      "Caller is not a valid attibute adder"
    );
    require(
      _traitsAdded[attribute.name()],
      "Attribute already exists on character"
    );
    _attributesAdded[attribute.name()] = true;
    _attributesMap[attribute.name()] = attribute;
    _attributesIndex[_attributeCount] = attribute;
    _attributeCount += 1;
  }

  /**
   * @dev
   */
  function getAttribute(string calldata name)
    external
    view
    returns (IAttribute)
  {
    return _attributesMap[name];
  }

  function getAttribute(uint256 index) external view returns (IAttribute) {
    return _attributesIndex[index];
  }

  function getTrait(string calldata name) external view returns (ITrait) {
    return _traitsMap[name];
  }

  function getIndex(uint256 index) external view returns (ITrait) {
    return _traitsIndex[index];
  }
}

