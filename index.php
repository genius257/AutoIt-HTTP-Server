<!DOCTYPE html>
<html>
	<head>
		<link href="https://fonts.googleapis.com/icon?family=Material+Icons" rel="stylesheet">
		<style>
			body{
				font-family:monospace;
			}
			th, td{
				padding:0 5px;
			}
			th{
				border-bottom:1px solid #000;
			}
			td:nth-child(4){
				text-align:right;
				white-space:pre;
			}
		</style>
	</head>
	<body>
		<h2>Index of <?=substr($_SERVER['REQUEST_URI'], 0, strrpos($_SERVER['REQUEST_URI'],"/")+1)?></h2>
		<table>
			<tr>
				<th></th>
				<th>Name</th>
				<th>Last modified</th>
				<th>Size</th>
			</tr>
			<tr>
				<td><i class="material-icons">&#xE5D9;</i></td>
				<td><a href="..">..</a></td>
				<td>-   </td>
				<td>-   </td>
			</tr>
			<?php
				// echo $_SERVER['SCRIPT_NAME'];
				// echo $_SERVER['REMOTE_ADDR'];
				// echo 'æøå';
				
				chdir('./www' . $_SERVER['REQUEST_URI']);
				
				$handle=opendir('.');
				$projectsListIgnore = array ('.','..');
				while (($file = readdir($handle))!==false)
				{
					if (is_dir($file) && !in_array($file,$projectsListIgnore))
					{
						?>
						<tr>
							<td>
								<i class="material-icons">&#xE2C7;</i>
							</td>
							<td>
								<a href="./<?=$file?>/"><?=$file?></a>
							</td>
							<td>
								<?=date("d-m-Y H:i:s", filectime($file)) ?>
							</td>
							<td>-   </td>
						</tr>
						<?php
					}
				}
				closedir($handle);
				
				$handle=opendir(".");
				while (($file = readdir($handle))!==false)
				{
					if (!is_dir($file))
					{
						?>
						<tr>
							<td>
								<i class="material-icons">&#xE24D;</i>
							</td>
							<td>
								<a href="./<?=$file?>"><?=$file?></a>
							</td>
							<td>
								<?=date("d-m-Y H:i:s", filectime($file)) ?>
							</td>
							<td><?php
									$size = filesize($file);
									if($size<1024){
										echo $size.' B ';
									}else{
										$size/=1024;
										if($size<1024){
											echo round($size,2).' KB';
										}else{
											echo round($size/1024,2)." MB";
										}
									}
									
								?></td>
						</tr>
						<?php
					}
				}
				closedir($handle);
			?>
		</table>
	</body>
</html>