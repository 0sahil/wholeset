#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Builds WholesetKit's built-in exercise library from free-exercise-db.

Source: https://github.com/yuhonas/free-exercise-db (Unlicense, public domain).
Download its `dist/exercises.json`, then run:

    python3 Scripts/curate-exercise-library.py path/to/exercises.json \
        WholesetKit/Sources/WholesetKit/Library/exercises.json

Only the entries listed in CURATED are kept, and of each only a stable key (the
upstream `id`), a display name, the equipment, the primary muscle and a few aliases
used to match names in imported workout files. Instructions and images are dropped.

Equipment mapping (upstream -> WholesetKit `Equipment` raw value):
    barbell -> barbell, e-z curl bar -> barbell,
    dumbbell -> dumbbell, cable -> cable, machine -> machine,
    body only -> bodyweight,
    kettlebells, bands, medicine ball, exercise ball, foam roll, other, none -> other.
A curated entry may override the mapped equipment or muscle, for example when the
upstream entry uses a band but commercial gyms use a machine for the same movement.

Muscle mapping: upstream primary muscles map one to one onto WholesetKit `Muscle` raw
values ("lower back" -> lowerBack, "middle back" -> middleBack); the first primary
muscle is used.
"""

import json
import sys

EQUIPMENT = {
    "barbell": "barbell",
    "e-z curl bar": "barbell",
    "dumbbell": "dumbbell",
    "cable": "cable",
    "machine": "machine",
    "body only": "bodyweight",
    "kettlebells": "other",
    "bands": "other",
    "medicine ball": "other",
    "exercise ball": "other",
    "foam roll": "other",
    "other": "other",
    None: "other",
}

MUSCLES = {
    "abdominals": "abdominals",
    "abductors": "abductors",
    "adductors": "adductors",
    "biceps": "biceps",
    "calves": "calves",
    "chest": "chest",
    "forearms": "forearms",
    "glutes": "glutes",
    "hamstrings": "hamstrings",
    "lats": "lats",
    "lower back": "lowerBack",
    "middle back": "middleBack",
    "neck": "neck",
    "quadriceps": "quadriceps",
    "shoulders": "shoulders",
    "traps": "traps",
    "triceps": "triceps",
}

# (upstream id, display name, extra aliases, overrides)
CURATED = [
    # Chest
    ("Barbell_Bench_Press_-_Medium_Grip", "Bench Press", ["Bench Press (Barbell)", "Barbell Bench Press", "Flat Bench Press"], {}),
    ("Barbell_Incline_Bench_Press_-_Medium_Grip", "Incline Bench Press", ["Incline Bench Press (Barbell)", "Incline Barbell Bench Press"], {}),
    ("Decline_Barbell_Bench_Press", "Decline Bench Press", ["Decline Bench Press (Barbell)"], {}),
    ("Wide-Grip_Barbell_Bench_Press", "Wide-Grip Bench Press", ["Bench Press - Wide Grip (Barbell)"], {}),
    ("Dumbbell_Bench_Press", "Dumbbell Bench Press", ["Bench Press (Dumbbell)", "DB Bench Press"], {}),
    ("Incline_Dumbbell_Press", "Incline Dumbbell Press", ["Incline Bench Press (Dumbbell)", "Incline DB Press", "Incline Dumbbell Bench Press"], {}),
    ("Decline_Dumbbell_Bench_Press", "Decline Dumbbell Press", ["Decline Bench Press (Dumbbell)"], {}),
    ("Dumbbell_Floor_Press", "Dumbbell Floor Press", ["Floor Press (Dumbbell)"], {"muscle": "chest"}),
    ("Dumbbell_Flyes", "Dumbbell Fly", ["Chest Fly (Dumbbell)", "Dumbbell Flye"], {}),
    ("Incline_Dumbbell_Flyes", "Incline Dumbbell Fly", ["Incline Chest Fly (Dumbbell)"], {}),
    ("Cable_Crossover", "Cable Fly", ["Cable Crossover (Cable)", "Chest Fly (Cable)", "Cable Chest Fly"], {}),
    ("Low_Cable_Crossover", "Low Cable Fly", ["Low to High Cable Fly", "Low Cable Crossover (Cable)"], {}),
    ("Butterfly", "Pec Deck", ["Chest Fly (Machine)", "Pec Deck (Machine)", "Machine Fly"], {}),
    ("Machine_Bench_Press", "Machine Chest Press", ["Chest Press (Machine)"], {}),
    ("Leverage_Incline_Chest_Press", "Incline Machine Press", ["Incline Chest Press (Machine)"], {}),
    ("Smith_Machine_Bench_Press", "Smith Machine Bench Press", ["Bench Press (Smith Machine)"], {}),
    ("Smith_Machine_Incline_Bench_Press", "Smith Machine Incline Press", ["Incline Bench Press (Smith Machine)"], {}),
    ("Pushups", "Push-up", ["Push Up", "Pushup", "Push Up (Bodyweight)"], {}),
    ("Dips_-_Chest_Version", "Chest Dip", ["Dips", "Chest Dip (Bodyweight)"], {"equipment": "bodyweight"}),
    ("Straight-Arm_Dumbbell_Pullover", "Dumbbell Pullover", ["Pullover (Dumbbell)"], {}),
    ("Standing_Cable_Chest_Press", "Cable Chest Press", ["Chest Press (Cable)"], {}),
    # Back
    ("Pullups", "Pull-up", ["Pull Up", "Pullup", "Pull Up (Bodyweight)"], {}),
    ("Chin-Up", "Chin-up", ["Chin Up", "Chinup", "Chin Up (Bodyweight)"], {}),
    ("Weighted_Pull_Ups", "Weighted Pull-up", ["Pull Up (Weighted)", "Weighted Pull Up"], {}),
    ("Band_Assisted_Pull-Up", "Assisted Pull-up", ["Pull Up (Assisted)", "Assisted Pull Up", "Band-Assisted Pull-up"], {"equipment": "machine"}),
    ("Wide-Grip_Lat_Pulldown", "Lat Pulldown", ["Lat Pulldown (Cable)", "Lat Pulldown (Machine)", "Wide-Grip Lat Pulldown"], {}),
    ("Close-Grip_Front_Lat_Pulldown", "Close-Grip Lat Pulldown", ["Lat Pulldown - Close Grip (Cable)"], {}),
    ("Underhand_Cable_Pulldowns", "Reverse-Grip Lat Pulldown", ["Lat Pulldown - Underhand (Cable)", "Underhand Lat Pulldown"], {}),
    ("One_Arm_Lat_Pulldown", "Single-Arm Lat Pulldown", ["Single Arm Lat Pulldown"], {}),
    ("Straight-Arm_Pulldown", "Straight-Arm Pulldown", ["Straight Arm Lat Pulldown (Cable)", "Straight Arm Pulldown"], {}),
    ("Seated_Cable_Rows", "Seated Cable Row", ["Seated Row (Cable)", "Cable Row", "Seated Cable Row - V Grip (Cable)"], {}),
    ("Seated_One-arm_Cable_Pulley_Rows", "Single-Arm Cable Row", ["Single Arm Cable Row"], {}),
    ("Bent_Over_Barbell_Row", "Barbell Row", ["Bent Over Row (Barbell)", "Bent-Over Row", "Barbell Bent Over Row"], {}),
    ("Reverse_Grip_Bent-Over_Rows", "Reverse-Grip Barbell Row", ["Underhand Barbell Row", "Bent Over Row - Underhand (Barbell)"], {}),
    ("One-Arm_Dumbbell_Row", "Dumbbell Row", ["Bent Over One Arm Row (Dumbbell)", "One-Arm Dumbbell Row", "Dumbbell Row (Dumbbell)"], {}),
    ("Bent_Over_Two-Dumbbell_Row", "Bent-Over Dumbbell Row", ["Bent Over Row (Dumbbell)"], {}),
    ("Dumbbell_Incline_Row", "Chest-Supported Dumbbell Row", ["Incline Row (Dumbbell)", "Incline Dumbbell Row"], {}),
    ("T-Bar_Row_with_Handle", "T-Bar Row", ["T Bar Row"], {}),
    ("Lying_T-Bar_Row", "Chest-Supported T-Bar Row", ["T Bar Row (Machine)"], {}),
    ("Leverage_High_Row", "Machine High Row", ["High Row (Machine)"], {}),
    ("Leverage_Iso_Row", "Machine Row", ["Seated Row (Machine)", "Iso-Lateral Row (Machine)"], {}),
    ("Inverted_Row", "Inverted Row", ["Inverted Row (Bodyweight)", "Bodyweight Row"], {"equipment": "bodyweight"}),
    ("Barbell_Deadlift", "Deadlift", ["Deadlift (Barbell)", "Conventional Deadlift", "Barbell Deadlift"], {}),
    ("Sumo_Deadlift", "Sumo Deadlift", ["Sumo Deadlift (Barbell)"], {}),
    ("Trap_Bar_Deadlift", "Trap Bar Deadlift", ["Deadlift (Trap bar)", "Hex Bar Deadlift"], {"equipment": "barbell"}),
    ("Rack_Pulls", "Rack Pull", ["Rack Pull (Barbell)"], {}),
    ("Deficit_Deadlift", "Deficit Deadlift", ["Deficit Deadlift (Barbell)"], {}),
    ("Hyperextensions_Back_Extensions", "Back Extension", ["Back Extension (Hyperextension)", "Hyperextension", "Back Extension (Machine)"], {"equipment": "bodyweight"}),
    ("Good_Morning", "Good Morning", ["Good Morning (Barbell)"], {}),
    ("Barbell_Shrug", "Barbell Shrug", ["Shrug (Barbell)"], {}),
    ("Dumbbell_Shrug", "Dumbbell Shrug", ["Shrug (Dumbbell)"], {}),
    ("Leverage_Shrug", "Machine Shrug", ["Shrug (Machine)"], {}),
    # Shoulders
    ("Standing_Military_Press", "Overhead Press", ["Overhead Press (Barbell)", "Military Press", "Strict Military Press (Barbell)", "OHP"], {}),
    ("Seated_Barbell_Military_Press", "Seated Overhead Press", ["Seated Overhead Press (Barbell)", "Seated Military Press"], {}),
    ("Dumbbell_Shoulder_Press", "Dumbbell Shoulder Press", ["Shoulder Press (Dumbbell)", "Overhead Press (Dumbbell)"], {}),
    ("Seated_Dumbbell_Press", "Seated Dumbbell Press", ["Seated Shoulder Press (Dumbbell)", "Seated Overhead Press (Dumbbell)"], {}),
    ("Arnold_Dumbbell_Press", "Arnold Press", ["Arnold Press (Dumbbell)"], {}),
    ("Machine_Shoulder_Military_Press", "Machine Shoulder Press", ["Shoulder Press (Machine)", "Overhead Press (Machine)"], {}),
    ("Smith_Machine_Overhead_Shoulder_Press", "Smith Machine Shoulder Press", ["Overhead Press (Smith Machine)"], {}),
    ("Push_Press", "Push Press", ["Push Press (Barbell)"], {}),
    ("Side_Lateral_Raise", "Lateral Raise", ["Lateral Raise (Dumbbell)", "Dumbbell Lateral Raise", "Side Lateral Raise"], {}),
    ("Standing_Low-Pulley_Deltoid_Raise", "Cable Lateral Raise", ["Lateral Raise (Cable)", "Single Arm Lateral Raise (Cable)"], {}),
    ("Lying_One-Arm_Lateral_Raise", "Lying Lateral Raise", ["Lying Lateral Raise (Dumbbell)"], {}),
    ("Front_Dumbbell_Raise", "Front Raise", ["Front Raise (Dumbbell)", "Dumbbell Front Raise"], {}),
    ("Front_Cable_Raise", "Cable Front Raise", ["Front Raise (Cable)"], {}),
    ("Front_Plate_Raise", "Plate Front Raise", ["Front Raise (Plate)"], {}),
    ("Reverse_Flyes", "Reverse Dumbbell Fly", ["Reverse Fly (Dumbbell)", "Rear Delt Fly (Dumbbell)"], {}),
    ("Seated_Bent-Over_Rear_Delt_Raise", "Bent-Over Rear Delt Raise", ["Rear Delt Raise (Dumbbell)", "Bent Over Lateral Raise (Dumbbell)"], {}),
    ("Reverse_Machine_Flyes", "Reverse Pec Deck", ["Reverse Fly (Machine)", "Rear Delt Fly (Machine)", "Rear Delt Machine"], {}),
    ("Cable_Rear_Delt_Fly", "Cable Rear Delt Fly", ["Rear Delt Fly (Cable)", "Reverse Fly (Cable)"], {}),
    ("Face_Pull", "Face Pull", ["Face Pull (Cable)", "Cable Face Pull"], {}),
    ("Upright_Barbell_Row", "Upright Row", ["Upright Row (Barbell)", "Barbell Upright Row"], {}),
    ("Standing_Dumbbell_Upright_Row", "Dumbbell Upright Row", ["Upright Row (Dumbbell)"], {}),
    ("Upright_Cable_Row", "Cable Upright Row", ["Upright Row (Cable)"], {}),
    ("External_Rotation_with_Cable", "Cable External Rotation", ["External Rotation (Cable)"], {}),
    # Biceps
    ("Barbell_Curl", "Barbell Curl", ["Bicep Curl (Barbell)", "Biceps Curl (Barbell)", "Barbell Bicep Curl"], {}),
    ("EZ-Bar_Curl", "EZ-Bar Curl", ["EZ Bar Biceps Curl", "Bicep Curl (EZ Bar)", "EZ Bar Curl"], {}),
    ("Dumbbell_Bicep_Curl", "Dumbbell Curl", ["Bicep Curl (Dumbbell)", "Biceps Curl (Dumbbell)", "Dumbbell Bicep Curl"], {}),
    ("Dumbbell_Alternate_Bicep_Curl", "Alternating Dumbbell Curl", ["Alternating Bicep Curl (Dumbbell)"], {}),
    ("Hammer_Curls", "Hammer Curl", ["Hammer Curl (Dumbbell)", "Dumbbell Hammer Curl"], {}),
    ("Incline_Dumbbell_Curl", "Incline Dumbbell Curl", ["Incline Curl (Dumbbell)"], {}),
    ("Concentration_Curls", "Concentration Curl", ["Concentration Curl (Dumbbell)"], {}),
    ("Preacher_Curl", "Preacher Curl", ["Preacher Curl (Barbell)", "Preacher Curl (EZ Bar)"], {}),
    ("Two-Arm_Dumbbell_Preacher_Curl", "Dumbbell Preacher Curl", ["Preacher Curl (Dumbbell)"], {}),
    ("Machine_Preacher_Curls", "Machine Preacher Curl", ["Preacher Curl (Machine)"], {}),
    ("Machine_Bicep_Curl", "Machine Bicep Curl", ["Bicep Curl (Machine)"], {}),
    ("Standing_Biceps_Cable_Curl", "Cable Curl", ["Bicep Curl (Cable)", "Cable Bicep Curl"], {}),
    ("Cable_Hammer_Curls_-_Rope_Attachment", "Rope Hammer Curl", ["Hammer Curl (Cable)", "Cable Hammer Curl"], {}),
    ("Spider_Curl", "Spider Curl", ["Spider Curl (Barbell)", "Spider Curl (EZ Bar)"], {}),
    ("Reverse_Barbell_Curl", "Reverse Curl", ["Reverse Curl (Barbell)", "Reverse Barbell Curl"], {}),
    # Triceps
    ("Triceps_Pushdown", "Triceps Pushdown", ["Triceps Pushdown (Cable - Straight Bar)", "Tricep Pushdown", "Cable Pushdown"], {}),
    ("Triceps_Pushdown_-_Rope_Attachment", "Rope Pushdown", ["Triceps Rope Pushdown", "Triceps Pushdown (Rope)", "Rope Tricep Pushdown"], {}),
    ("Reverse_Grip_Triceps_Pushdown", "Reverse-Grip Pushdown", ["Reverse Grip Triceps Pushdown (Cable)"], {}),
    ("Triceps_Overhead_Extension_with_Rope", "Overhead Cable Triceps Extension", ["Overhead Triceps Extension (Cable)", "Rope Overhead Triceps Extension"], {}),
    ("EZ-Bar_Skullcrusher", "Skull Crusher", ["Skullcrusher (Barbell)", "Skullcrusher (EZ Bar)", "Lying Triceps Extension (EZ Bar)"], {}),
    ("Close-Grip_Barbell_Bench_Press", "Close-Grip Bench Press", ["Bench Press - Close Grip (Barbell)", "Close Grip Bench Press"], {}),
    ("Dips_-_Triceps_Version", "Triceps Dip", ["Triceps Dip (Bodyweight)", "Tricep Dips"], {}),
    ("Bench_Dips", "Bench Dip", ["Bench Dip (Bodyweight)", "Bench Dips"], {}),
    ("Tricep_Dumbbell_Kickback", "Dumbbell Kickback", ["Triceps Kickback (Dumbbell)", "Tricep Kickback"], {}),
    ("Standing_Dumbbell_Triceps_Extension", "Dumbbell Overhead Triceps Extension", ["Overhead Triceps Extension (Dumbbell)", "Triceps Extension (Dumbbell)"], {}),
    ("Lying_Dumbbell_Tricep_Extension", "Lying Dumbbell Triceps Extension", ["Lying Triceps Extension (Dumbbell)"], {}),
    ("Machine_Triceps_Extension", "Machine Triceps Extension", ["Triceps Extension (Machine)"], {}),
    ("Dip_Machine", "Machine Dip", ["Seated Dip (Machine)", "Triceps Dip (Assisted)"], {}),
    ("Push-Ups_-_Close_Triceps_Position", "Close-Grip Push-up", ["Diamond Push Up", "Close Grip Push Up"], {}),
    # Quadriceps
    ("Barbell_Squat", "Squat", ["Squat (Barbell)", "Back Squat", "Barbell Back Squat"], {}),
    ("Front_Barbell_Squat", "Front Squat", ["Front Squat (Barbell)"], {}),
    ("Box_Squat", "Box Squat", ["Box Squat (Barbell)"], {}),
    ("Goblet_Squat", "Goblet Squat", ["Goblet Squat (Kettlebell)", "Goblet Squat (Dumbbell)"], {"equipment": "dumbbell"}),
    ("Dumbbell_Squat", "Dumbbell Squat", ["Squat (Dumbbell)"], {}),
    ("Hack_Squat", "Hack Squat", ["Hack Squat (Machine)"], {}),
    ("Smith_Machine_Squat", "Smith Machine Squat", ["Squat (Smith Machine)"], {}),
    ("Bodyweight_Squat", "Bodyweight Squat", ["Air Squat", "Squat (Bodyweight)"], {}),
    ("Leg_Press", "Leg Press", ["Leg Press (Machine)"], {}),
    ("Narrow_Stance_Leg_Press", "Narrow-Stance Leg Press", ["Leg Press - Narrow Stance (Machine)"], {}),
    ("Leg_Extensions", "Leg Extension", ["Leg Extension (Machine)"], {}),
    ("Barbell_Lunge", "Barbell Lunge", ["Lunge (Barbell)"], {}),
    ("Dumbbell_Lunges", "Dumbbell Lunge", ["Lunge (Dumbbell)"], {}),
    ("Dumbbell_Rear_Lunge", "Reverse Lunge", ["Reverse Lunge (Dumbbell)"], {}),
    ("Bodyweight_Walking_Lunge", "Walking Lunge", ["Walking Lunge (Bodyweight)", "Walking Lunge (Dumbbell)"], {"equipment": "bodyweight"}),
    ("Split_Squat_with_Dumbbells", "Bulgarian Split Squat", ["Bulgarian Split Squat (Dumbbell)", "Rear Foot Elevated Split Squat"], {}),
    ("Dumbbell_Step_Ups", "Step-up", ["Step Up (Dumbbell)", "Dumbbell Step-up", "Step Up"], {}),
    # Hamstrings and glutes
    ("Romanian_Deadlift", "Romanian Deadlift", ["Romanian Deadlift (Barbell)", "RDL"], {}),
    ("Stiff-Legged_Barbell_Deadlift", "Stiff-Legged Deadlift", ["Straight Leg Deadlift (Barbell)", "Stiff Leg Deadlift"], {}),
    ("Stiff-Legged_Dumbbell_Deadlift", "Dumbbell Romanian Deadlift", ["Romanian Deadlift (Dumbbell)", "Dumbbell RDL"], {}),
    ("Lying_Leg_Curls", "Leg Curl", ["Lying Leg Curl (Machine)", "Lying Leg Curl", "Leg Curl (Machine)"], {}),
    ("Seated_Leg_Curl", "Seated Leg Curl", ["Seated Leg Curl (Machine)"], {}),
    ("Standing_Leg_Curl", "Standing Leg Curl", ["Standing Leg Curl (Machine)"], {}),
    ("Glute_Ham_Raise", "Glute-Ham Raise", ["Glute Ham Raise"], {}),
    ("Barbell_Hip_Thrust", "Hip Thrust", ["Hip Thrust (Barbell)", "Barbell Hip Thrust"], {}),
    ("Barbell_Glute_Bridge", "Glute Bridge", ["Glute Bridge (Barbell)"], {}),
    ("One-Legged_Cable_Kickback", "Cable Glute Kickback", ["Glute Kickback (Cable)", "Cable Kickback"], {}),
    ("Pull_Through", "Cable Pull-Through", ["Cable Pull Through", "Pull Through (Cable)"], {}),
    ("Thigh_Abductor", "Hip Abduction", ["Hip Abductor (Machine)", "Abductor Machine"], {}),
    ("Thigh_Adductor", "Hip Adduction", ["Hip Adductor (Machine)", "Adductor Machine"], {}),
    ("One-Arm_Kettlebell_Swings", "Kettlebell Swing", ["Kettlebell Swing (Kettlebell)", "KB Swing"], {}),
    # Calves
    ("Standing_Calf_Raises", "Standing Calf Raise", ["Standing Calf Raise (Machine)", "Calf Raise (Machine)"], {}),
    ("Seated_Calf_Raise", "Seated Calf Raise", ["Seated Calf Raise (Machine)"], {}),
    ("Calf_Press_On_The_Leg_Press_Machine", "Leg Press Calf Raise", ["Calf Press on Leg Press", "Calf Press (Machine)"], {}),
    ("Standing_Dumbbell_Calf_Raise", "Dumbbell Calf Raise", ["Calf Raise (Dumbbell)"], {}),
    ("Smith_Machine_Calf_Raise", "Smith Machine Calf Raise", ["Calf Raise (Smith Machine)"], {}),
    # Core
    ("Plank", "Plank", ["Plank (Bodyweight)"], {}),
    ("Side_Bridge", "Side Plank", ["Side Bridge"], {}),
    ("Crunches", "Crunch", ["Crunch (Bodyweight)", "Crunches"], {}),
    ("Cable_Crunch", "Cable Crunch", ["Kneeling Cable Crunch", "Crunch (Cable)"], {}),
    ("Ab_Crunch_Machine", "Machine Crunch", ["Crunch (Machine)", "Ab Crunch Machine"], {}),
    ("Decline_Crunch", "Decline Crunch", ["Decline Crunch (Bodyweight)"], {}),
    ("Reverse_Crunch", "Reverse Crunch", ["Reverse Crunch (Bodyweight)"], {}),
    ("Sit-Up", "Sit-up", ["Sit Up", "Situp"], {}),
    ("Hanging_Leg_Raise", "Hanging Leg Raise", ["Hanging Leg Raise (Bodyweight)"], {}),
    ("Flat_Bench_Lying_Leg_Raise", "Lying Leg Raise", ["Leg Raise", "Lying Leg Raise (Bodyweight)"], {}),
    ("Ab_Roller", "Ab Wheel Rollout", ["Ab Wheel", "Ab Roller"], {}),
    ("Russian_Twist", "Russian Twist", ["Russian Twist (Bodyweight)"], {}),
    ("Pallof_Press", "Pallof Press", ["Pallof Press (Cable)"], {}),
    ("Standing_Cable_Wood_Chop", "Cable Woodchop", ["Wood Chop (Cable)", "Cable Wood Chop"], {}),
    ("Dumbbell_Side_Bend", "Dumbbell Side Bend", ["Side Bend (Dumbbell)"], {}),
    # Forearms
    ("Palms-Up_Barbell_Wrist_Curl_Over_A_Bench", "Wrist Curl", ["Wrist Curl (Barbell)"], {}),
    ("Palms-Down_Wrist_Curl_Over_A_Bench", "Reverse Wrist Curl", ["Reverse Wrist Curl (Barbell)"], {}),
    # Olympic lifts most often seen in commercial gyms
    ("Power_Clean", "Power Clean", ["Power Clean (Barbell)"], {}),
    ("Clean_and_Press", "Clean and Press", ["Clean and Press (Barbell)"], {}),
]

SOURCE = "free-exercise-db, https://github.com/yuhonas/free-exercise-db"
LICENSE = "Unlicense (public domain)"


def fold(text):
    return text.strip().lower()


def main(upstream_path, output_path):
    upstream = {entry["id"]: entry for entry in json.load(open(upstream_path, encoding="utf-8"))}
    exercises = []
    for key, name, extra_aliases, overrides in CURATED:
        if key not in upstream:
            sys.exit("Unknown upstream id: " + key)
        entry = upstream[key]
        muscles = entry.get("primaryMuscles") or []
        if not muscles:
            sys.exit("No primary muscle for: " + key)
        equipment = overrides.get("equipment", EQUIPMENT[entry.get("equipment")])
        muscle = overrides.get("muscle", MUSCLES[muscles[0]])
        aliases = []
        for alias in [entry["name"]] + extra_aliases:
            if fold(alias) != fold(name) and fold(alias) not in {fold(a) for a in aliases}:
                aliases.append(alias)
        exercises.append({
            "key": key,
            "name": name,
            "equipment": equipment,
            "muscle": muscle,
            "aliases": aliases,
        })

    names = {}
    for exercise in exercises:
        for label in [exercise["name"]] + exercise["aliases"]:
            owner = names.setdefault(fold(label), exercise["key"])
            if owner != exercise["key"]:
                sys.exit("Name or alias used twice: %r (%s, %s)" % (label, owner, exercise["key"]))

    exercises.sort(key=lambda exercise: fold(exercise["name"]))
    library = {"source": SOURCE, "license": LICENSE, "exercises": exercises}
    with open(output_path, "w", encoding="utf-8") as handle:
        json.dump(library, handle, indent=2, ensure_ascii=False)
        handle.write("\n")
    print("Wrote %d exercises to %s" % (len(exercises), output_path))


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit("usage: curate-exercise-library.py <upstream exercises.json> <output exercises.json>")
    main(sys.argv[1], sys.argv[2])
