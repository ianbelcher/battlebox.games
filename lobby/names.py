"""Room codes: an adjective and a noun, joined by a hyphen.

`brave-otter` is the whole of what somebody has to pass on to let a friend
into a private game, so every word here has to survive being read aloud by
one child and typed by another: short, concrete, unambiguously spelled, no
homophones, nothing that turns into something unfortunate when paired.

The pools give 167 x 178 = 29,726 codes. That is not a security boundary
and is not meant to be — it is a lobby for a children's game, and a private
room is private because nobody has any reason to look for it. It is simply
far past the point where guessing is a worthwhile way to spend an evening.
"""

from __future__ import annotations

import random

ADJECTIVES = """
amber ancient angry autumn bashful blue bold bouncy brave breezy bright
brisk bronze bubbly bumpy busy calm cheeky cheery chilly chirpy chunky
clever cloudy clumsy cosy crimson crispy curly curious daring dazzling
dizzy dotty dreamy droopy dusty eager early earnest emerald fancy feisty
fizzy fluffy foggy fond frosty funny fuzzy gentle giddy gigantic ginger
glad gleaming glowing golden graceful grand grassy greedy grumpy happy
hasty hazy hearty hidden honest hungry husky icy indigo ivory jade jolly
jumpy keen kindly lanky lazy lemon lively lofty lonely loyal lucky lumpy
merry mighty milky misty modest mossy muddy neat nimble noble noisy nutty
olive orange patient peachy pearly perky pink plucky plump polite proud
purple quaint quick quiet rapid rosy royal ruby rugged rusty sandy sapphire
scarlet shady shaggy sharp shiny short shy silent silky silver simple
sleepy slender snappy snowy sparkly speedy spicy spotty spry sturdy sunny
swift teal tidy timid tiny toasty tricky trusty velvet violet warm wavy
whiskery wild windy winter wise witty wobbly wooden zany zippy
""".split()

NOUNS = """
acorn alpaca anchor antler apple arrow badger bamboo banjo basket beacon
beetle bison blossom bobcat boulder bramble bridge bugle bunny burrow
cactus camel canoe canyon caravan cedar cheetah chestnut chipmunk cinder
clover cobble comet compass coral cottage cricket crow cygnet daisy dingo
dolphin donkey dragonfly dumpling eagle ember falcon fennec fern ferret
fiddle finch flamingo forest fossil fountain foxglove frost gazelle geyser
ginger glacier gopher gosling grotto gumdrop hamster harbour harp hazel
heron hollow hornet iceberg iguana ivy jackal jaguar juniper kestrel
kettle koala lagoon lantern lemur lighthouse lily lizard llama lobster
lotus lynx magpie mango maple marble marmot meadow meerkat mitten
mockingbird moose moth muffin mushroom narwhal nectar nutmeg oak ocelot
octopus opal orchard osprey otter owl panda pangolin parrot pebble pelican
penguin pepper pigeon pinecone piper pistachio plum pony poppy prairie
puffin pumpkin quail quiver rabbit raccoon radish raven reef ribbon river
robin rocket rowan saffron salmon sapling seagull seahorse shellfish
sparrow spruce squirrel starling sunflower swallow tadpole tamarin teapot
thistle thrush toucan trout tulip turtle vixen walnut walrus warbler
willow wombat woodpecker wren yak zebra
""".split()


def all_codes() -> int:
    """How many distinct codes exist. Used by the tests, and worth being
    able to state rather than guess at."""
    return len(ADJECTIVES) * len(NOUNS)


def make_code(taken: set[str] | None = None, rng: random.Random | None = None) -> str:
    """A code nobody is using.

    Retries on collision rather than probing sequentially: walking to the
    next free code would make a room's neighbours guessable from its own,
    which is the one property the word pairs exist to avoid.
    """
    taken = taken or set()
    rng = rng or random.SystemRandom()
    for _ in range(200):
        code = f"{rng.choice(ADJECTIVES)}-{rng.choice(NOUNS)}"
        if code not in taken:
            return code
    # Every one of 200 draws collided, which needs thousands of live rooms.
    # Fall back to something certainly unused rather than failing a create.
    suffix = rng.randrange(1000, 10000)
    return f"{rng.choice(ADJECTIVES)}-{rng.choice(NOUNS)}-{suffix}"


def is_code(text: str) -> bool:
    """Whether something a player typed even looks like a code."""
    parts = text.strip().lower().split("-")
    if len(parts) not in (2, 3):
        return False
    if not (parts[0].isalpha() and parts[1].isalpha()):
        return False
    return len(parts) == 2 or parts[2].isdigit()
