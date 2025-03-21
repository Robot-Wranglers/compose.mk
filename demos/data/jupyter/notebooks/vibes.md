---
jupyter:
  jupytext:
    formats: ipynb,md
    notebook_metadata_filter: language_info
    text_representation:
      extension: .md
      format_name: markdown
      format_version: '1.3'
      jupytext_version: 1.16.7
  kernelspec:
    display_name: Python 3 (ipykernel)
    language: python
    name: python3
  language_info:
    codemirror_mode:
      name: ipython
      version: 3
    file_extension: .py
    mimetype: text/x-python
    name: python
    nbconvert_exporter: python
    pygments_lexer: ipython3
    version: 3.11.2
---

## Vibes Coding

----------------------

**This notebook is vibes coded.**  If your own vibes are everywhere-continuous but nowhere differentiable, then you might enjoy some visualizations of the Weierstrass function and these other sundries.  The point of this notebook is just to generate various kinds of plots, testing how the images will render in pipeline-mode notebook previews.

-------------------

```python
import numpy as np
import matplotlib.pyplot as plt
from mpl_toolkits.mplot3d import Axes3D
from mpl_toolkits.mplot3d.art3d import Poly3DCollection
from matplotlib.patches import Polygon

# Create figure with 3 subplots in a row
fig = plt.figure(figsize=(16, 5))

# High contrast settings
plt.rcParams['lines.linewidth'] = 2.5
plt.rcParams['axes.linewidth'] = 2.0
plt.rcParams['grid.linewidth'] = 1.5
plt.rcParams['patch.linewidth'] = 2.0
background_color = '#000000'
foreground_color = '#FFFFFF'
colors = ['#00FFFF', '#FF00FF', '#FFFF00', '#00FF00', '#FF0000']
fig.patch.set_facecolor(background_color)

# 1. Regular Pentagon (2D polygon)
ax1 = fig.add_subplot(131)
n = 5  # Pentagon
r = 1  # Radius
theta = np.linspace(0, 2*np.pi, n, endpoint=False)
x = r * np.cos(theta)
y = r * np.sin(theta)
pentagon = Polygon(np.column_stack([x, y]), fill=False, edgecolor=colors[0], linewidth=3)
ax1.add_patch(pentagon)
ax1.set_xlim(-1.2, 1.2)
ax1.set_ylim(-1.2, 1.2)
ax1.set_aspect('equal')
ax1.set_title('Pentagon (2D Polygon)', color=foreground_color, fontsize=14, fontweight='bold')
ax1.grid(True, linewidth=1.5, color='gray', alpha=0.6)
ax1.set_facecolor(background_color)
ax1.spines['bottom'].set_color(foreground_color)
ax1.spines['top'].set_color(foreground_color)
ax1.spines['left'].set_color(foreground_color)
ax1.spines['right'].set_color(foreground_color)
ax1.tick_params(colors=foreground_color)

# 2. Icosahedron (3D polyhedron with 20 triangular faces)
ax2 = fig.add_subplot(132, projection='3d')
ax2.set_facecolor(background_color)

# Define the 12 vertices of an icosahedron
phi = (1 + np.sqrt(5)) / 2  # Golden ratio
vertices = np.array([
    [0, 1, phi], [0, -1, phi], [0, 1, -phi], [0, -1, -phi],
    [1, phi, 0], [-1, phi, 0], [1, -phi, 0], [-1, -phi, 0],
    [phi, 0, 1], [-phi, 0, 1], [phi, 0, -1], [-phi, 0, -1]
])
# Normalize vertices to lie on unit sphere
vertices = vertices / np.sqrt(1 + phi**2)

# Define the 20 triangular faces
faces = [
    [vertices[0], vertices[1], vertices[8]],
    [vertices[0], vertices[1], vertices[9]],
    [vertices[0], vertices[4], vertices[8]],
    [vertices[0], vertices[4], vertices[5]],
    [vertices[0], vertices[5], vertices[9]],
    [vertices[1], vertices[6], vertices[8]],
    [vertices[1], vertices[6], vertices[7]],
    [vertices[1], vertices[7], vertices[9]],
    [vertices[2], vertices[3], vertices[10]],
    [vertices[2], vertices[3], vertices[11]],
    [vertices[2], vertices[4], vertices[10]],
    [vertices[2], vertices[4], vertices[5]],
    [vertices[2], vertices[5], vertices[11]],
    [vertices[3], vertices[6], vertices[10]],
    [vertices[3], vertices[6], vertices[7]],
    [vertices[3], vertices[7], vertices[11]],
    [vertices[4], vertices[8], vertices[10]],
    [vertices[5], vertices[9], vertices[11]],
    [vertices[6], vertices[8], vertices[10]],
    [vertices[7], vertices[9], vertices[11]]
]

ax2.add_collection3d(Poly3DCollection(faces, alpha=0.35, facecolor=colors[1], linewidths=2.5, edgecolor=foreground_color))
ax2.set_xlim(-1, 1)
ax2.set_ylim(-1, 1)
ax2.set_zlim(-1, 1)
ax2.set_title('Icosahedron (3D Polyhedron)', color=foreground_color, fontsize=14, fontweight='bold')
ax2.xaxis.pane.fill = False
ax2.yaxis.pane.fill = False
ax2.zaxis.pane.fill = False
ax2.xaxis.pane.set_edgecolor(foreground_color)
ax2.yaxis.pane.set_edgecolor(foreground_color)
ax2.zaxis.pane.set_edgecolor(foreground_color)
ax2.tick_params(colors=foreground_color)

# 3. Tesseract (4D Polytope)
ax3 = fig.add_subplot(133, projection='3d')
ax3.set_facecolor(background_color)

# Define the vertices of the inner cube
inner_vertices = 0.5 * np.array([
    [-1, -1, -1], [1, -1, -1], [1, 1, -1], [-1, 1, -1],
    [-1, -1, 1], [1, -1, 1], [1, 1, 1], [-1, 1, 1]
])

# Define the vertices of the outer cube
outer_vertices = np.array([
    [-1, -1, -1], [1, -1, -1], [1, 1, -1], [-1, 1, -1],
    [-1, -1, 1], [1, -1, 1], [1, 1, 1], [-1, 1, 1]
])

# Draw inner cube
faces = []
for i in range(6):
    if i == 0:
        face = [inner_vertices[0], inner_vertices[1], inner_vertices[2], inner_vertices[3]]
    elif i == 1:
        face = [inner_vertices[4], inner_vertices[5], inner_vertices[6], inner_vertices[7]]
    elif i == 2:
        face = [inner_vertices[0], inner_vertices[1], inner_vertices[5], inner_vertices[4]]
    elif i == 3:
        face = [inner_vertices[2], inner_vertices[3], inner_vertices[7], inner_vertices[6]]
    elif i == 4:
        face = [inner_vertices[0], inner_vertices[3], inner_vertices[7], inner_vertices[4]]
    else:
        face = [inner_vertices[1], inner_vertices[2], inner_vertices[6], inner_vertices[5]]
    faces.append(face)

inner_cube = Poly3DCollection(faces, alpha=0.35, facecolor=colors[2], linewidths=2.5, edgecolor=foreground_color)
ax3.add_collection3d(inner_cube)

# Draw outer cube
faces = []
for i in range(6):
    if i == 0:
        face = [outer_vertices[0], outer_vertices[1], outer_vertices[2], outer_vertices[3]]
    elif i == 1:
        face = [outer_vertices[4], outer_vertices[5], outer_vertices[6], outer_vertices[7]]
    elif i == 2:
        face = [outer_vertices[0], outer_vertices[1], outer_vertices[5], outer_vertices[4]]
    elif i == 3:
        face = [outer_vertices[2], outer_vertices[3], outer_vertices[7], outer_vertices[6]]
    elif i == 4:
        face = [outer_vertices[0], outer_vertices[3], outer_vertices[7], outer_vertices[4]]
    else:
        face = [outer_vertices[1], outer_vertices[2], outer_vertices[6], outer_vertices[5]]
    faces.append(face)

outer_cube = Poly3DCollection(faces, alpha=0.2, facecolor=colors[3], linewidths=2.5, edgecolor=foreground_color)
ax3.add_collection3d(outer_cube)

# Connect corresponding vertices of inner and outer cubes (projecting 4D connections)
for i in range(8):
    ax3.plot([inner_vertices[i][0], outer_vertices[i][0]],
             [inner_vertices[i][1], outer_vertices[i][1]],
             [inner_vertices[i][2], outer_vertices[i][2]], color=foreground_color, alpha=0.8, linewidth=2.5)

ax3.set_xlim(-1.5, 1.5)
ax3.set_ylim(-1.5, 1.5)
ax3.set_zlim(-1.5, 1.5)
ax3.set_title('Tesseract Projection (4D Polytope)', color=foreground_color, fontsize=14, fontweight='bold')
ax3.xaxis.pane.fill = False
ax3.yaxis.pane.fill = False
ax3.zaxis.pane.fill = False
ax3.xaxis.pane.set_edgecolor(foreground_color)
ax3.yaxis.pane.set_edgecolor(foreground_color)
ax3.zaxis.pane.set_edgecolor(foreground_color)
ax3.tick_params(colors=foreground_color)

plt.tight_layout()
plt.show()
```
------------------------------------------------------------------

```python
import numpy as np
import matplotlib.pyplot as plt
from matplotlib.gridspec import GridSpec
from mpl_toolkits.mplot3d import Axes3D
from mpl_toolkits.mplot3d.art3d import Poly3DCollection
import matplotlib.patches as patches

def weierstrass(x, a, b, N):
    """Compute the Weierstrass function: W(x) = Σ(n=0 to N) a^n * cos(b^n * π * x)"""
    result = np.zeros_like(x, dtype=float)
    for n in range(N+1):
        result += a**n * np.cos(b**n * np.pi * x)
    return result

def create_dodecahedron():
    """Create vertices and faces for a dodecahedron"""
    phi = (1 + np.sqrt(5)) / 2
    
    vertices = np.array([
        [1, 1, 1], [1, 1, -1], [1, -1, 1], [1, -1, -1],
        [-1, 1, 1], [-1, 1, -1], [-1, -1, 1], [-1, -1, -1],
        [0, phi, 1/phi], [0, phi, -1/phi], [0, -phi, 1/phi], [0, -phi, -1/phi],
        [1/phi, 0, phi], [1/phi, 0, -phi], [-1/phi, 0, phi], [-1/phi, 0, -phi],
        [phi, 1/phi, 0], [phi, -1/phi, 0], [-phi, 1/phi, 0], [-phi, -1/phi, 0]
    ])
    
    vertices = vertices / np.linalg.norm(vertices[0])
    
    faces = [
        [0, 16, 2, 12, 8], [0, 8, 4, 14, 12], [16, 17, 18, 2, 0], 
        [8, 9, 4, 0, 16], [12, 14, 19, 3, 2], [12, 2, 18, 10, 14],
        [14, 10, 11, 5, 19], [14, 19, 3, 13, 11], [4, 9, 15, 6, 14], 
        [14, 6, 7, 11, 10], [19, 5, 15, 9, 8], [19, 8, 0, 16, 17],
    ]
    
    return vertices, faces

def create_icosahedron():
    """Create vertices and faces for an icosahedron"""
    phi = (1 + np.sqrt(5)) / 2
    
    vertices = np.array([
        [0, 1, phi], [0, 1, -phi], [0, -1, phi], [0, -1, -phi],
        [1, phi, 0], [1, -phi, 0], [-1, phi, 0], [-1, -phi, 0],
        [phi, 0, 1], [phi, 0, -1], [-phi, 0, 1], [-phi, 0, -1]
    ])
    
    vertices = vertices / np.linalg.norm(vertices[0])
    
    faces = [
        [0, 2, 8], [0, 8, 4], [0, 4, 6], [0, 6, 10], [0, 10, 2],
        [1, 3, 9], [1, 9, 4], [1, 4, 6], [1, 6, 11], [1, 11, 3],
        [2, 3, 5], [2, 5, 8], [2, 7, 3], [2, 10, 7], 
        [3, 7, 11], [3, 11, 5], [4, 5, 8], [4, 8, 9], 
        [4, 9, 5], [5, 9, 3], [6, 7, 10], [6, 10, 11], 
        [6, 11, 7], [7, 10, 11]
    ]
    
    return vertices, faces

def create_4d_tesseract_projection():
    """Create vertices and edges for a 3D projection of a 4D tesseract (hypercube)"""
    # 16 vertices of 4D tesseract
    vertices_4d = np.array([
        [1, 1, 1, 1], [1, 1, 1, -1], [1, 1, -1, 1], [1, 1, -1, -1],
        [1, -1, 1, 1], [1, -1, 1, -1], [1, -1, -1, 1], [1, -1, -1, -1],
        [-1, 1, 1, 1], [-1, 1, 1, -1], [-1, 1, -1, 1], [-1, 1, -1, -1],
        [-1, -1, 1, 1], [-1, -1, 1, -1], [-1, -1, -1, 1], [-1, -1, -1, -1]
    ])
    
    # Project 4D to 3D using stereographic projection
    vertices = np.zeros((16, 3))
    for i, v in enumerate(vertices_4d):
        w = 1.5 / (2 - v[3])  # Projection factor
        vertices[i] = [v[0] * w, v[1] * w, v[2] * w]
    
    # Define edges of tesseract
    edges = []
    for i in range(16):
        for j in range(i+1, 16):
            # Connect vertices that differ in exactly one coordinate
            diff = np.sum(np.abs(vertices_4d[i] - vertices_4d[j]))
            if diff == 2:  # In 4D hypercube, vertices are connected if they differ in 1 dimension
                edges.append([i, j])
    
    return vertices, edges

def create_regular_polygon(n):
    """Create vertices for a regular n-gon"""
    angles = np.linspace(0, 2 * np.pi, n, endpoint=False)
    vertices = np.array([np.cos(angles), np.sin(angles)]).T
    return vertices

# Parameters
a = 0.5
b = 5
max_N = 8

# Create a larger figure
fig = plt.figure(figsize=(16, 15))

# Create three rows with custom heights
gs = GridSpec(3, 1, height_ratios=[1, 1, 0.8], figure=fig, hspace=0.4)

# Top row - Weierstrass function
ax1 = fig.add_subplot(gs[0])

# Middle row - 4 geometric shapes
gs_middle = GridSpec(1, 4, figure=fig, wspace=0.4)
gs_middle.update(top=0.62, bottom=0.38)  # Explicitly position the middle row

ax2_1 = fig.add_subplot(gs_middle[0], aspect='equal')  # 2D polygon
ax2_2 = fig.add_subplot(gs_middle[1], projection='3d')  # Dodecahedron
ax2_3 = fig.add_subplot(gs_middle[2], projection='3d')  # Icosahedron
ax2_4 = fig.add_subplot(gs_middle[3], projection='3d')  # 4D Tesseract projection

# Bottom row - Progressive construction
ax3 = fig.add_subplot(gs[2])

# Calculate and plot the Weierstrass function
x = np.linspace(-2, 2, 10000)
final_weierstrass = weierstrass(x, a, b, max_N)

ax1.plot(x, final_weierstrass, 'k-', linewidth=1)
ax1.set_title(f'Weierstrass Function: $W(x) = \\sum_{{n=0}}^{{{max_N}}} {a}^n \\cos({b}^n \\pi x)$', fontsize=14)
ax1.set_xlabel('x')
ax1.set_ylabel('W(x)')
ax1.grid(True, alpha=0.3)

# Create zoom plot
zoom_ax = ax1.inset_axes([0.6, 0.1, 0.35, 0.35])
zoom_region = (-0.2, 0.2)
zoom_ax.plot(x, final_weierstrass, 'k-', linewidth=0.8)
zoom_ax.set_xlim(zoom_region)
zoom_ax.set_ylim(
    np.min(final_weierstrass[(x >= zoom_region[0]) & (x <= zoom_region[1])]) - 0.1,
    np.max(final_weierstrass[(x >= zoom_region[0]) & (x <= zoom_region[1])]) + 0.1
)
zoom_ax.set_title('Zoomed Region', fontsize=10)
zoom_ax.grid(True, alpha=0.3)
ax1.indicate_inset_zoom(zoom_ax, edgecolor="red")

# 1. Regular polygon (2D)
n_sides = 12
polygon_vertices = create_regular_polygon(n_sides)
polygon = patches.Polygon(polygon_vertices, closed=True, alpha=0.7, facecolor='lightblue', edgecolor='blue')
ax2_1.add_patch(polygon)

# Add vertices
ax2_1.scatter(polygon_vertices[:, 0], polygon_vertices[:, 1], color='red', s=50, zorder=3)

# Add numbers for vertices
for i, (x, y) in enumerate(polygon_vertices):
    ax2_1.text(x*1.1, y*1.1, str(i+1), fontsize=9, ha='center', va='center')

# Add diagonals to show symmetry
for i in range(n_sides):
    for j in range(i+2, n_sides):
        if j != i+1 and j != (i-1) % n_sides:
            ax2_1.plot([polygon_vertices[i, 0], polygon_vertices[j, 0]], 
                      [polygon_vertices[i, 1], polygon_vertices[j, 1]], 
                      'gray', alpha=0.3, linestyle='--')

ax2_1.set_xlim(-1.3, 1.3)
ax2_1.set_ylim(-1.3, 1.3)
ax2_1.set_title(f'Regular {n_sides}-gon', fontsize=12)
ax2_1.set_aspect('equal')
ax2_1.axis('off')

# 2. Dodecahedron (3D)
vertices, faces = create_dodecahedron()
colors = plt.cm.viridis(np.linspace(0, 1, len(faces)))

for i, face in enumerate(faces):
    face_vertices = vertices[face]
    poly = Poly3DCollection([face_vertices], alpha=0.8, linewidths=1, edgecolors='k')
    poly.set_facecolor(colors[i])
    ax2_2.add_collection3d(poly)

ax2_2.set_xlim(-1.5, 1.5)
ax2_2.set_ylim(-1.5, 1.5)
ax2_2.set_zlim(-1.5, 1.5)
ax2_2.set_title('Dodecahedron', fontsize=12)
ax2_2.set_box_aspect([1, 1, 1])
ax2_2.axis('off')

# 3. Icosahedron (3D)
vertices, faces = create_icosahedron()
colors = plt.cm.plasma(np.linspace(0, 1, len(faces)))

for i, face in enumerate(faces):
    face_vertices = vertices[face]
    poly = Poly3DCollection([face_vertices], alpha=0.8, linewidths=1, edgecolors='k')
    poly.set_facecolor(colors[i])
    ax2_3.add_collection3d(poly)

ax2_3.set_xlim(-1.5, 1.5)
ax2_3.set_ylim(-1.5, 1.5)
ax2_3.set_zlim(-1.5, 1.5)
ax2_3.set_title('Icosahedron', fontsize=12)
ax2_3.set_box_aspect([1, 1, 1])
ax2_3.axis('off')

# 4. Tesseract (4D → 3D projection)
vertices, edges = create_4d_tesseract_projection()

# Draw edges
for edge in edges:
    xs = [vertices[edge[0]][0], vertices[edge[1]][0]]
    ys = [vertices[edge[0]][1], vertices[edge[1]][1]]
    zs = [vertices[edge[0]][2], vertices[edge[1]][2]]
    ax2_4.plot(xs, ys, zs, 'k-', linewidth=1, alpha=0.7)

# Draw vertices
color_map = np.linspace(0, 1, 16)
for i, v in enumerate(vertices):
    ax2_4.scatter(v[0], v[1], v[2], color=plt.cm.coolwarm(color_map[i]), s=50)

ax2_4.set_xlim(-3, 3)
ax2_4.set_ylim(-3, 3)
ax2_4.set_zlim(-3, 3)
ax2_4.set_title('Tesseract (4D Hypercube) Projection', fontsize=12)
ax2_4.set_box_aspect([1, 1, 1])
ax2_4.axis('off')

# Bottom plot - progressive construction
x_terms = np.linspace(-2, 2, 1000)
color_scheme = plt.cm.viridis(np.linspace(0, 1, max_N+1))

for n in range(max_N+1):
    partial_sum = weierstrass(x_terms, a, b, n)
    if n in [0, 1, 3, max_N]:
        ax3.plot(x_terms, partial_sum, color=color_scheme[n], linewidth=2.5, 
                 label=f'N = {n}')

ax3.set_title('Progressive Construction of Weierstrass Function', fontsize=12)
ax3.set_xlabel('x')
ax3.set_ylabel('Partial Sum')
ax3.grid(True, alpha=0.3)
ax3.legend(fontsize=9, loc='upper right')

# plt.tight_layout()
plt.show()
```

------------------------------------------

```python
import numpy as np
import matplotlib.pyplot as plt
from matplotlib.gridspec import GridSpec

def weierstrass(x, a, b, N):
    """
    Compute the Weierstrass function:
    W(x) = Σ(n=0 to N) a^n * cos(b^n * π * x)
    
    Parameters:
    x: x-coordinate value or array
    a: amplitude factor (0 < a < 1)
    b: frequency factor (positive odd integer)
    N: number of terms to include in the sum
    
    Returns:
    Value of the Weierstrass function at x
    """
    result = np.zeros_like(x, dtype=float)
    for n in range(N+1):
        result += a**n * np.cos(b**n * np.pi * x)
    return result

# Parameters
a = 0.5       # amplitude factor (0 < a < 1)
b = 20         # frequency factor (positive odd integer)
max_N = 6     # maximum number of terms

# Ensure condition for nowhere-differentiability: a*b > 1 + 3π/2
assert a * b > 1 + 3*np.pi/2, "Parameters a and b don't satisfy a*b > 1 + 3π/2 required for nowhere-differentiability"

# Create plot
fig = plt.figure(figsize=(14, 16))
gs = GridSpec(3, 1, height_ratios=[2, 1, 1], figure=fig)

# Main plot showing the final function
ax1 = fig.add_subplot(gs[0])
ax2 = fig.add_subplot(gs[1])
ax3 = fig.add_subplot(gs[2])

# Global x values (high resolution for the final function)
x = np.linspace(-2, 2, 10000)
final_weierstrass = weierstrass(x, a, b, max_N)

# Plot the final Weierstrass function
ax1.plot(x, final_weierstrass, 'k-', linewidth=1)
ax1.set_title(f'Weierstrass Function: $W(x) = \\sum_{{n=0}}^{{{max_N}}} {a}^n \\cos({b}^n \\pi x)$', fontsize=14)
ax1.set_xlabel('x')
ax1.set_ylabel('W(x)')
ax1.grid(True, alpha=0.3)

# Plot showing progressive addition of terms
x_terms = np.linspace(-2, 2, 1000)  # Fewer points for individual terms
colors = plt.cm.viridis(np.linspace(0, 1, max_N+1))

for n in range(max_N+1):
    term = a**n * np.cos(b**n * np.pi * x_terms)
    ax2.plot(x_terms, term, color=colors[n], linewidth=2, 
             label=f'$a^{{{n}}} \\cos(b^{{{n}}} \\pi x)$' if n <= 3 else '')

ax2.set_title('Individual Terms of the Sum', fontsize=12)
ax2.set_xlabel('x')
ax2.set_ylabel('Term Value')
ax2.grid(True, alpha=0.3)
ax2.legend(fontsize=9, loc='upper right')

# Plot showing progressive construction, each adding one more term
partial_sums = []
for n in range(max_N+1):
    partial_sum = weierstrass(x_terms, a, b, n)
    partial_sums.append(partial_sum)
    if n in [0, 1, 3, max_N]:  # Only plot a few for clarity
        ax3.plot(x_terms, partial_sum, color=colors[n], linewidth=1, 
                 label=f'N = {n}')

ax3.set_title('Progressive Construction of Weierstrass Function', fontsize=12)
ax3.set_xlabel('x')
ax3.set_ylabel('Partial Sum')
ax3.grid(True, alpha=0.9)
ax3.legend(fontsize=9, loc='upper right')
# Zoom plot to show fractal-like nature
zoom_ax = ax3.inset_axes([.1, 0.1, 0.35, 0.35])
zoom_region = (-0.5, 0.5)
zoom_ax.plot(x, final_weierstrass, 'k-', linewidth=0.3)
zoom_ax.set_xlim(zoom_region)
zoom_ax.set_ylim(
    np.min(final_weierstrass[(x >= zoom_region[0]) & (x <= zoom_region[1])]) - 0.1,
    np.max(final_weierstrass[(x >= zoom_region[0]) & (x <= zoom_region[1])]) + 0.1
)
zoom_ax.set_title('Zoomed Region', fontsize=10)
zoom_ax.grid(True, alpha=0.9)
ax3.indicate_inset_zoom(zoom_ax, edgecolor="red",linewidth=3)

# Zoom plot to show fractal-like nature
zoom_ax = ax1.inset_axes([0.6, 0.1, 0.35, 0.35])
zoom_region = (-0.2, 0.2)
zoom_ax.plot(x, final_weierstrass, 'k-', linewidth=0.5)
for spine in zoom_ax.spines.values(): spine.set_edgecolor('red')  # Change to any color
zoom_ax.set_xlim(zoom_region)
zoom_ax.set_ylim(
    np.min(final_weierstrass[(x >= zoom_region[0]) & (x <= zoom_region[1])]) - 0.1,
    np.max(final_weierstrass[(x >= zoom_region[0]) & (x <= zoom_region[1])]) + 0.1
)
zoom_ax.set_title('Zoomed Region', fontsize=10)
zoom_ax.grid(True, alpha=0.3)
# Connect zoom region
ax1.indicate_inset_zoom(zoom_ax, edgecolor="red",linewidth=3)

plt.tight_layout()
plt.show()
```
