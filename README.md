# Godot ML Trainer

Godot, unlike other popular game engines, is a completely free platform that makes for great photorealistic simulations.  This project contains all the basic GDScript and a bootstrap scene that's easy to hack on top of for your
physics or vision-based ML model to learn from.

## Example Problem

Your noob competitor's helicopter bots keep dropping apple crates all over the country.  You being way cooler, have only a day to train your way advanced quadcopters how to prioritize saving all the spilt apples before they start to rot! Having no real world data to draw from, you quickly realize the best way to recover the goods is by always picking up the highest object in the stack of mess, which disturbs the rest of the cargo the least.  You grab the Godot physics engine, some 3d scans of what your quadcopters need to pick up, and viola, you run a million simulations of the following to teach your quadcopters what to prioritize without ever leaving your beloved chair!

# Example Solution Details

Since the quadcopters will traverse vast diverse landscapes, we want to train against randomized versions of what they'd see in the real world, ideally a large superset of whatever might actually be seen.  To accomplish this almost
every aspect of the simulation is randomized:

- Lighting: # of lights, light color, intensity etc.
- Ground: Different Earthy backgrounds, and some weird ones just in case.  Lots of randomized color and scaling.
- Objects: Objects vary up to 10% in size, random colors and start positions.
- Camera: Very high and very low views with random camera rotation

The output is a CSV containing image references and bounding boxes around the highest object found in the images.  The CSV writing logic can be adapted to fit whatever your model's software requires.  Check out the `gcp` branch
to generate a Google Machine Vision friendly version of the CSV file.

# TODO: Results

(Post results of model here after training)

## Training Data Generation Tips

1. Randomize everything.  You can always narrow to more real-world scenarios toward the end of your ML's training, but with earlier stages of training hyper randomization is almost never a bad thing and forces early generalization before
specializing more on less random, more predictable real-world data.  For storage reasons this repo uses only apples and crates, but an unrealistically large set of objects would produce a more general model.
2. Validate training labels.  Be sure to watch yuor simulation and think through edge cases that could result in impossible-to-predict labels such as off-screen bounding boxes.  This is especially imnportant if you do a good job at tip #1.
3. Manually validate labels.  Incorrect labels produce useless models, correctness is everything, take the time to visually debug your labels when possible, which is supported in this repo as the DebugLayer.
4. Iterate.  When you think you've randomized well enough, quickly train against it to see where you might have holes in your parameter randomization.  Try to use tooling that can show you most incorrect predictions and use them to
prioritize the next set of sim features you randomize.

## Installing

1. Download Godot version 3.2 (maybe greater?)
2. Clone this repository
3. Open Godot, select Import, select project file type (not zip), and browse for this project's project.godot file (in godot-ml-trainer).
4. Make sure the "snapshots" folder exists as a neighbor of the "godot-ml-trainer" folder (or change location in `main.gd`).
5. Click the Play button on the upper-right!
6. Hack away at main.gd until you've got the sim you need.

## Godot vs X

Unity is also a great game engine for photorealistic simulations, though much more complex and a higher learning curve.  GDScript is very Pythonic and fairly friendly for the data science community.  Unity is best for very advanced simulation,
and Godot for basic or intermediate complexity.
