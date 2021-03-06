# VERSION 0.2 (DRAFT 3 June 2018) CONSISTING OF 5 COMPONENTS:
# preprocessing.r, optimisation.r, run_optimisation.r, postprocessing.r, functions.r
# Contact: Hawthorne Beyer, h.beyer@uq.edu.au

library(raster)

rcompose = function(in.ras, ext=r.ext){
  if(is.character(in.ras)){in.ras=raster(in.ras)}
  res = crop(in.ras, ext)
  return(res)
}

calc.objective.function <- function(form, bd, cb, oc, w.cb=1, w.bd=1, wrld.form=NULL){
  if (form == 'wrld') {form = c('cb-bd-oc', 'cb', 'bd', 'oc')[wrld.form]}
  #print(form)
	if (form == "cb-bd"){
		return((w.cb * cb) + (w.bd * bd))
	} else {
		if (form == "cb-bd-oc"){
			return(((w.cb * cb) + (w.bd * bd)) / oc)
		} else {
			if (form == "bd"){
				return(bd)
			} else {
				if (form == "bd-oc"){
					return(bd / oc)
				} else {
					if (form == "cb"){
						return(cb)
					} else {
						if (form == "cb-oc"){
							return(cb / oc)
						} else {
							if (form == "oc"){
								return((-oc + abs(min(-oc)) + 1))
							} else {
								message("ERROR: undefined objective function form")
								return(NULL)	
							}
						}
					}
				}
			}
		}		
	}
}


# test the objective function calculation manually
test.objective.function <- function(){
	bd <- 10
	cb <- 5
	oc <- 2

	ans <- c(15, 10, 5, 7.5, 5, 2.5, 10, 5, 5, 2.5, 1)
	res <- rep(0, 11)
	res[1] <- calc.objective.function("cb-bd", bd, cb, oc, w.cb=1, w.bd=1)
	res[2] <- calc.objective.function("cb-bd", bd, cb, oc, w.cb=0, w.bd=1)
	res[3] <- calc.objective.function("cb-bd", bd, cb, oc, w.cb=1, w.bd=0)
	res[4] <- calc.objective.function("cb-bd-oc", bd, cb, oc, w.cb=1, w.bd=1)
	res[5] <- calc.objective.function("cb-bd-oc", bd, cb, oc, w.cb=0, w.bd=1)
	res[6] <- calc.objective.function("cb-bd-oc", bd, cb, oc, w.cb=1, w.bd=0)
	res[7] <- calc.objective.function("bd", bd, cb, oc, w.cb=1, w.bd=1)
	res[8] <- calc.objective.function("bd-oc", bd, cb, oc, w.cb=1, w.bd=1)
	res[9] <- calc.objective.function("cb", bd, cb, oc, w.cb=1, w.bd=1)
	res[10] <- calc.objective.function("cb-oc", bd, cb, oc, w.cb=1, w.bd=1)
	res[11] <- calc.objective.function("oc", bd, cb, oc, w.cb=1, w.bd=1)

	return(data.frame(res, ans, diff=res-ans))
}


# important to implement this as a function because there is good potential for speed-up with this code and we do not want to have to change this many times in optimisation.r
# also, this is some of the code that is easiest to mess up
calc.bd <- function(slp){
	bd <- rep(0, np)
	for (i in 1:dim(usphab_proc)[1]){
		hab.values <- prop.restore %*% usphab_proc[i,]
		for (j in 1:length(usphab_index[[i]])){
			if (!is.null(species_index_list_proc[[usphab_index[[i]][j]]])){
				recs <- species_index_list_proc[[usphab_index[[i]][j]]]
				bd[recs] <- bd[recs] + slp[usphab_index[[i]][j]] * hab.values[recs]
			}
		}
		
	}
	bd <- bd * g_scalar_bd
	return(bd)
}



# function to calculate extinction risk
# A: current area
# Amax: maximum potential area
extinction.risk <- function(A, Amax, z=0.25){
	r <- 1 - (A/Amax)^z
	recs <- which(r < 0)
	if (length(recs) > 0) r[recs] <- 0
	return(r)
}


# returns positive values for weightings, even though the slopes are actually negative
calc.extinction.slope <- function(A, Amax, z=0.25){
	er1 <- extinction.risk(A, Amax, z=z)
	er2 <- extinction.risk(A+1E-6, Amax, z=z)
	res <- (er2 - er1) / 1E-6	
	return(abs(res))
}


# mapping function (requires the raster r.terr is pre-loaded)
plot.pu.map <- function(v, fname=NULL, bias=1,
                        info=F, area.print=F, weight.print=F, step.count=F,
                        localize=F, save.raster=F){
  v.in = v
	require(raster)
  #colfunc <-   colorRampPalette(c('lightgrey', "#00007F", "blue", "#007FFF",
  #                                "cyan", "#7FFF7F", "yellow", "#FF7F00", "red",
  #                                "#7F0000"))
  colfunc = colorRampPalette(c('black', 'lightgrey', c("royalblue", "#007FFF","cyan",
                                                       "#7FFF7F", "yellow", "#FF7F00", "red",
                                                       "#7F0000")[9:1]))
  if (area.print) {a.info = paste0(round(sum(v)*A),' sq.km | ')} else {a.info=''}
  #if (localize) {colfunc = colorRampPalette(c('darkgrey', 'lightgrey', 'green')); v[v>0] = 1; v[v==0]=0.5}
  if (localize) {v[v>0] = 1; v[v==0]=1/10}
	#colfunc <- colorRampPalette(c("green4", "green", "yellow", "orange", "red", "red4"), bias=bias)
	#colfunc <- colorRampPalette(c('lightgrey', "green2", "cyan", "blue"), bias=bias)
	cols <- colfunc(100)
	r <- r.terr
	r[r==0] <- NA
	r[r==1] <- 0
	values(r)[master_index] <- v
	if (step.count) {s.info = paste0(' (', s, '/', nsteps,'): ')} else {s.info=': '}
	if (weight.print) {w.info = paste0(' (', w.cb, ' CB, ', w.bd, ' BD)')} else {w.info=''}
	if (!is.null(fname)){
	  png(file=fname, width=2000, height=1000)
	  if (info) {par(mar=c(0,0,2.1,0))} else {par(mar=c(0,0,0,0))}
	  plot(r.terr, xlim=c(-1.2E7, 1.6E7), ylim=c(-6.5E6, 8828767),
	       col=c("white", "grey90"), axes=F, box=!info, legend=F,
	       main=ifelse(info, paste0(save.name, s.info, a.info, length(v), ' px', w.info), ''))
	  plot(r, xlim=c(-1.2E7, 1.6E7), ylim=c(-6.5E6, 8828767), col=cols,
	       axes=F, box=!info, add=T)
	  dev.off()	  
	} else {
	  plot(r, xlim=c(-1.2E7, 1.6E7), ylim=c(-6.5E6, 8828767), col=cols, axes=F, box=!info,
	       main=ifelse(info, paste0(save.name, s.info, a.info, length(v), ' px', w.info),''))
	}
	if (save.raster){writeRaster(r, filename = sub('.png', '.tif', fname), overwrite=T)}
	return(r)
}

# function to write a raster based on the master_index vector
write.pu.raster <- function(v, fname=NULL){
	require(raster)
  colfunc <-   colorRampPalette(c("#00007F", "blue", "#007FFF", "cyan",
                                  "#7FFF7F", "yellow", "#FF7F00", "red",
                                  "#7F0000"))
  cols <- colfunc(100)
	r <- r.terr
	r[r==0] <- NA
	r[r==1] <- 0
	values(r)[master_index] <- v
	if (!is.null(fname)){writeRaster(r, filename=fname)} else {
	  plot(r, xlim=c(-1.2E7, 1.6E7), ylim=c(-6.5E6, 8828767), col=cols)}
	return()
}

# area of a lat lon cell

area.latlon <- function(lon1, lon2, lat1, lat2){
	# surface area = S in km2
	# radius of earth = R

	R <- 6371.0072
	S <- R^2 * ((max(lon1, lon2) * pi / 180) - (min(lon1, lon2) * pi / 180)) * (sin((max(lat1, lat2) * pi / 180)) - sin(min(lat1, lat2) * pi / 180))
	return(S)
}

#area.latlon(0, 1, 0, 1)^0.5

# returns the selected index postitions of master_index
random.allocation <- function(area.target, area.available){
	ord <- sample(c(1:length(area.available)), length(area.available), replace=FALSE)
	cumarea <- cumsum(area.available[ord])
	rec <- which(cumarea > area.target)[1] - 1
	if (!is.na(rec)){rec=1}
	return(ord[1:rec])
}


postprocess.results <- function(dir, outdir, scen, hasweights=TRUE){
  
  if (hasweights){
    load(file=paste0(outdir, scen, "_weightm.RData"))
    load(file=paste0(dir, "exrisk.t0.RData"))
    load(file=paste0(dir, "cb.RData"))
    load(file=paste0(dir, "ocg.RData"))
    load(file=paste0(dir, "occ.RData"))
    load(file=paste0(dir, "prop.crop.RData"))
    load(file=paste0(dir, "prop.cultg.RData"))
    oc <- (prop.crop / (prop.crop + prop.cultg)) * occ + (prop.cultg / (prop.crop + prop.cultg)) * ocg 
    
    exrisk.mean <- rep(0, dim(weightm)[1])
    exrisk.sum <- rep(0, dim(weightm)[1])
    exrisk.red.mean.abs <- rep(0, dim(weightm)[1])
    exrisk.red.sum.abs <- rep(0, dim(weightm)[1])
    cb.total <- rep(0, dim(weightm)[1])
    oc.total <- rep(0, dim(weightm)[1])
    area.rest <- rep(0, dim(weightm)[1])
    
    for (w in 1:dim(weightm)[1]){
      load(file=paste0(outdir, scen, "_res.exrisk_w_", w, ".RData"))
      nsteps <- dim(res.exrisk)[2]
      exrisk.mean[w] <- mean(res.exrisk[,nsteps])
      exrisk.sum[w] <- sum(res.exrisk[,nsteps])
      exrisk.red.mean.abs[w] <-  mean(exrisk.t0 - res.exrisk[,nsteps]) * const_bd
      exrisk.red.sum.abs[w] <-  sum(exrisk.t0 - res.exrisk[,nsteps]) * const_bd
      #exrisk.red.mean.prop[w] <-  mean((exrisk.t0 - res.exrisk[,nsteps]) / exrisk.t0)
      
      load(file=paste0(outdir, scen, "_res.total.restored.pu_w_", w, ".RData"))
      cb.total[w] <- sum(cb * res.total.restored.pu * A * const_cb)
      oc.total[w] <- sum(oc * res.total.restored.pu * A * const_oc)
      area.rest[w] <- sum(res.total.restored.pu * A * const_area)
    }
    
    df <- data.frame(scenario=rep(scen, dim(weightm)[1]), weightcb=weightm[,1],
                     weightbd=weightm[,2], exrisk.mean, exrisk.sum,
                     exrisk.red.mean.abs, exrisk.red.sum.abs,
                     cb.total, oc.total, area.rest)
    
  } else {
    w <- "1"
    load(file=paste0(dir, "exrisk.t0.RData"))
    load(file=paste0(dir, "cb.RData"))
    load(file=paste0(dir, "ocg.RData"))
    load(file=paste0(dir, "occ.RData"))
    load(file=paste0(dir, "prop.crop.RData"))
    load(file=paste0(dir, "prop.cultg.RData"))
    oc <- (prop.crop / (prop.crop + prop.cultg)) * occ +
      (prop.cultg / (prop.crop + prop.cultg)) * ocg 
    
    load(file=paste0(outdir, scen, "_res.exrisk_w_", w, ".RData"))
    nsteps <- dim(res.exrisk)[2]
    exrisk.mean <- mean(res.exrisk[,nsteps])
    exrisk.sum <- sum(res.exrisk[,nsteps])
    exrisk.red.mean.abs <-  mean(exrisk.t0 - res.exrisk[,nsteps]) * const_bd
    exrisk.red.sum.abs <-  sum(exrisk.t0 - res.exrisk[,nsteps]) * const_bd
    load(file=paste0(outdir, scen, "_res.total.restored.pu_w_", w, ".RData"))
    cb.total <- sum(cb * res.total.restored.pu * A * const_cb)
    oc.total <- sum(oc * res.total.restored.pu * A * const_oc)
    area.rest <- sum(res.total.restored.pu * A * const_area)
    
    df <- data.frame(scenario=scen, weightcb=NA, weightbd=NA, exrisk.mean,
                     exrisk.sum, exrisk.red.mean.abs, exrisk.red.sum.abs,
                     cb.total, oc.total, area.rest)
  }
  
  save(df, file=paste0(outdir, scen, "_results_df.RData"))
  print(df)
  return(df)
}


postprocess.grad <- function(dir, outdir, ns, filename){

    w <- "1"
    load(file=paste0(dir, "exrisk.t0.RData"))
    load(file=paste0(dir, "cb.RData"))
    load(file=paste0(dir, "ocg.RData"))
    load(file=paste0(dir, "occ.RData"))
    load(file=paste0(dir, "prop.crop.RData"))
    load(file=paste0(dir, "prop.cultg.RData"))
    load(file=paste0(dir, "prop.restore.RData"))
    
    oc <- (prop.crop / (prop.crop + prop.cultg)) * occ +
      (prop.cultg / (prop.crop + prop.cultg)) * ocg 
    
    load(file=paste0(outdir, scen, "_res.exrisk_w_", w, ".RData"))
    nsteps <- dim(res.exrisk)[2]
    exrisk.sum <- colSums(res.exrisk)
    load(file=paste0(outdir, filename))
    cb.total <- sum(cb * res.total.restored.pu * A * const_cb)
    oc.total <- sum(oc * res.total.restored.pu * A * const_oc)
    Forests.rest <- sum(res.total.restored.pu * A * prop.restore[,1] * const_area)
    Wetlands.rest <- sum(res.total.restored.pu * A * prop.restore[,2] * const_area)
    Deserts.rest <- sum(res.total.restored.pu * A * prop.restore[,3] * const_area)
    Grasslands.rest <- sum(res.total.restored.pu * A * prop.restore[,4] * const_area)
    Shrublands.rest <- sum(res.total.restored.pu * A * prop.restore[,5] * const_area)
    
    
    df <- data.frame(scenario=paste0(scen,'-step_',ns),
                     weightcb=NA, weightbd=NA, exrisk.sum = exrisk.sum[ns],
                     cb.total, oc.total, Forests.rest, Wetlands.rest,
                     Deserts.rest, Grasslands.rest, Shrublands.rest)
    print(df)
    return(df)
}




