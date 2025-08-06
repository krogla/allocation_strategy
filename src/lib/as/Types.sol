// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.28;

import {Fixed32x32} from "../utils/Fixed32x32.sol";
import {PackedBytes32} from "../utils/PackedBytes32.sol";

/// @dev The main internal concept of AS is the concept of weight for an entity, on the
/// basis of which it is possible to construct a distribution of something across
/// these entities. Each entity has a set of parameters, each of which collectively
/// affects the final weight of the entity. The set itself and the order of parameters
/// in it are the same for all entities; only the values differ. In fact, it is a table
/// where entities are listed in rows and parameters are listed in columns. Each such
/// column (element in the set) is a parameter category. Thus, each entity in the table
/// has values from several categories.
/// Each category has its own ID and can store any unified values from 0 to 10,000. The
/// interpretation of these values into meaningful numbers is left to the user's discretion.
/// The number of categories is limited to 16 elements. Not all categories need to be used
/// simultaneously; the number of necessary categories is set through configuration and
/// determines N categories from the beginning that will be taken into account in the
/// calculations. If a category is used, its values must be defined for all entities;
/// there cannot be a situation where some entities have values from one category and
/// some from another.
type Category is uint8; // max 16 categories, store 16 uint16 in one bytes32

/// @dev  The strategy is a combination (set) of parameter categories that are used to
/// calculate the final weight of the entity. Different strategies can be used
/// for different purposes, such as calculating the weight of an entity in a specific
/// context or for a specific task. It is allows using same categories in different
/// strategies, but with different proportion weights. The number of strategies is
/// limited to 256.
type Strategy is uint8;

struct Config {
    bool initialized; // true if config is initialized
    uint8 categoriesCount; // number of param types, max 16 MUST be set during initialization
        // PackedBytes32 defaultParamValues; // default absolute values of params for entities, i.e. [bond, fee, perf], according to `ParamTypes` enum
}

struct Entity {
    bool disabled;
    string name;
}

/*
 * The `ValueCountWeight` type is 96 bits long, and packs the following:
 *
 * ```
 *   | [uint16]: absolute value (value)
 *   |   | [uint16]: value unique counter (count)
 *   ↓   ↓   ↓ [uint64]: value calculated weight in Fixed32.32 (weight)
 * 0xAAAABBBBCCCCCCCCCCCCCCCC
 * ```
 */

type ValueCountWeight is uint96;

struct ValueCountWeightStruct {
    uint16 value; // value in range 0…10_000 inclusive
    uint16 count; // count of value in the original array
    Fixed32x32 weight; // weight in 32.32 fixed-point format
}

struct CategoryValuesState {
    bool isDirty; // flag to indicate that the state has been changed and needs to be updated
    ValueCountWeight[] vcWeights; // array of value statistics, i.e. packed value, count and weights
}

struct StrategyState {
    // mapping of strategies to packed bytes32, each uint16 represents a param type weight,
    // zero value means skip params type for this strategy
    // ! assuming weights are not normalized, i.e. sum of weights can be not equal to 1,
    // so weights will be calculated dynamically at the moment of final weight calculation
    PackedBytes32 _categoryCorrectionWeights;
    // mapping(Category => Fixed32x32[]) _entityCategoryFinalWeights; //?
    Fixed32x32[] _strategyEntityFinalWeights; // weights for all param types, used to calculate final weights for strategies
}

struct AllocationStrategyStorage {
    Config _config;
    Entity[] _entities; //general info about entities
    PackedBytes32[] _entityCategoryValueIndexes; // array of entity's param value indexes, i.e. [bondIdx, feeIdx, perfIdx] for each entity
    mapping(Category => CategoryValuesState) _categoryStates; // mapping of param types to their states, i.e. value counts and nonce
    mapping(Strategy => StrategyState) _strategyStates; // mapping of strategies to their states
}
